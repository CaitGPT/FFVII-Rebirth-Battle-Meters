// Battle Meters native hit probe (development only, issue 1). A UE4SS C++ mod that watches ProcessEvent for the game's
// per-hit Blueprint events and logs each call with its parameters to hits.log next to this DLL. It changes nothing in
// the game.
//
// Why native: Lua RegisterHook on Blueprint overrides never fires in this game's UE4SS 3.0.1 (live, 2026-11-08), but
// the engine still dispatches those events through UObject::ProcessEvent, which UE4SS hooks for everyone. Matching is
// one integer compare per ProcessEvent: the called function's FName index against the indexes of the native
// declarations, which Blueprint overrides share by name. The callback is registered at load, never during play.
#include <Windows.h>
#include <Mod/CppUserModBase.hpp>
#include <Unreal/UObjectGlobals.hpp>
#include <Unreal/UObject.hpp>
#include <Unreal/UClass.hpp>
#include <Unreal/UFunction.hpp>
#include <Unreal/FProperty.hpp>
#include <Unreal/Property/FBoolProperty.hpp>
#include <Unreal/NameTypes.hpp>

#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

namespace RC::Unreal::Hook
{
    // Exact declaration from the installed UEPseudo (see the telemetry exporter); the template headers omit it.
    using ProcessEventCallback = std::function<void(UObject*, UFunction*, void*)>;
    RC_UE_API auto RegisterProcessEventPreCallback(ProcessEventCallback) -> void;
}

namespace BattleMetersNativeHits
{
    using namespace RC::Unreal;

    // The native declarations whose names the Blueprint overrides share. OnActionInvoke runs all the time, as a control.
    constexpr std::array<const wchar_t*, 8> WATCHED{
        L"/Script/EndGame.EndBattleSceneBlueprint:OnTakeDamage",
        L"/Script/EndGame.EndBattleSceneBlueprint:OnIncrementBattleCountPerID",
        L"/Script/EndGame.EndBattleSceneBlueprint:OnCharaPartsDamage",
        L"/Script/EndGame.EndAIControllerBluePrintBase:OnTakeDamageInvoke",
        L"/Script/EndGame.EndAIControllerBluePrintBase:OnTakeDamageHPFirstInvoke",
        L"/Script/EndGame.EndAIControllerBluePrintBase:OnGiveDamageInvoke",
        L"/Script/EndGame.EndAIControllerBluePrintBase:OnTakeDamageOverTime",
        L"/Script/EndGame.EndAIControllerBluePrintBase:OnActionInvoke",
    };
    constexpr size_t CONTROL = 7;           // OnActionInvoke: counted, logged only a few times
    constexpr uint64_t CONTROL_LINES = 5;

    struct Param
    {
        std::wstring name;
        std::wstring type;
        int32_t offset{};
        FBoolProperty* boolean{};
    };

    struct Probe
    {
        std::mutex mutex;
        std::vector<std::string> pending;                          // lines waiting for the writer thread
        std::array<uint32_t, WATCHED.size()> indexes{};            // FName comparison index per watched name
        std::array<std::atomic<uint64_t>, WATCHED.size()> calls{};
        std::unordered_map<UFunction*, std::vector<Param>> layouts; // game thread only
        // The callback's own cost, for the frame-drop investigation: every ProcessEvent it sees, and the time spent in it.
        std::atomic<uint64_t> seen{};
        std::atomic<uint64_t> spent_ticks{};
        std::atomic<uint64_t> max_ticks{};
        std::atomic<uint64_t> matched_ticks{};
        int64_t tick_frequency{1};
        std::atomic<bool> running{true};
        std::wstring path;
    };
    Probe* g_probe{};

    // UObjectBase::GetNamePrivate() const, looked up by its exported name. The pinned headers declare FName as a struct and
    // the installed DLL exports it as a class, so the linker can't match the header's declaration. It returns a reference
    // to the object's FName, whose first 32 bits are the comparison index.
    using GetNamePrivateFn = const uint32_t* (*)(const void* self);
    GetNamePrivateFn g_get_name_private{};

    uint32_t name_index(const UObject* object)
    {
        if (!object || !g_get_name_private) return 0;
        const uint32_t* name = g_get_name_private(object);
        return name ? name[0] : 0;
    }

    std::string narrow(const std::wstring& text)
    {
        std::string out;
        out.reserve(text.size());
        for (wchar_t c : text) out.push_back(c >= 32 && c < 127 && c != '"' && c != '\\' ? static_cast<char>(c) : '?');
        return out;
    }

    uint64_t now_ms()
    {
        return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now().time_since_epoch()).count());
    }

    void queue(std::string line)
    {
        std::lock_guard guard(g_probe->mutex);
        if (g_probe->pending.size() < 20000) g_probe->pending.push_back(std::move(line));
    }

    std::vector<Param>& layout_of(UFunction* function)
    {
        auto found = g_probe->layouts.find(function);
        if (found != g_probe->layouts.end()) return found->second;
        std::vector<Param> params;
        for (FProperty* property : function->ForEachProperty())
        {
            Param param{property->GetName(), property->GetClass().GetName(), property->GetOffset_Internal()};
            if (param.type == L"BoolProperty") param.boolean = static_cast<FBoolProperty*>(property);
            params.push_back(std::move(param));
        }
        auto& stored = g_probe->layouts[function];
        stored = std::move(params);
        std::string described = "layout " + narrow(function->GetFullName()) + ":";
        for (const auto& p : stored) described += " " + narrow(p.name) + "(" + narrow(p.type) + "@" + std::to_string(p.offset) + ")";
        queue(described);
        return stored;
    }

    std::string decode(UFunction* function, void* parms)
    {
        std::string out;
        if (!parms) return out;
        for (const auto& p : layout_of(function))
        {
            auto* at = static_cast<uint8_t*>(parms) + p.offset;
            std::string value;
            if (p.type == L"IntProperty") value = std::to_string(*reinterpret_cast<int32_t*>(at));
            else if (p.type == L"FloatProperty") value = std::to_string(*reinterpret_cast<float*>(at));
            else if (p.type == L"NameProperty") value = narrow(reinterpret_cast<FName*>(at)->ToString());
            else if (p.type == L"BoolProperty" && p.boolean) value = p.boolean->GetPropertyValue(at) ? "true" : "false";
            else if (p.type == L"ByteProperty" || p.type == L"EnumProperty") value = std::to_string(*at);
            else if (p.type == L"ObjectProperty")
            {
                auto* object = *reinterpret_cast<UObject**>(at);
                value = object ? narrow(object->GetName()) : "null";
            }
            else continue;
            out += " " + narrow(p.name) + "=" + value;
        }
        return out;
    }

    void match(UObject* context, UFunction* function, void* parms)
    {
        const uint32_t index = name_index(function);
        for (size_t i = 0; i < WATCHED.size(); ++i)
        {
            if (g_probe->indexes[i] == 0 || g_probe->indexes[i] != index) continue;
            const uint64_t n = ++g_probe->calls[i];
            if (i == CONTROL && n > CONTROL_LINES) return;
            LARGE_INTEGER start{}, end{};
            QueryPerformanceCounter(&start);
            std::string line = std::to_string(now_ms()) + " " + narrow(function->GetName()) + " #" + std::to_string(n) +
                " on " + (context ? narrow(context->GetName()) : std::string("null")) +
                " fn " + narrow(function->GetFullName()) + decode(function, parms);
            queue(std::move(line));
            QueryPerformanceCounter(&end);
            g_probe->matched_ticks += static_cast<uint64_t>(end.QuadPart - start.QuadPart);
            return;
        }
    }

    void on_process_event(UObject* context, UFunction* function, void* parms)
    {
        if (!function) return;
        LARGE_INTEGER start{}, end{};
        QueryPerformanceCounter(&start);
        match(context, function, parms);
        QueryPerformanceCounter(&end);
        const auto ticks = static_cast<uint64_t>(end.QuadPart - start.QuadPart);
        ++g_probe->seen;
        g_probe->spent_ticks += ticks;
        if (ticks > g_probe->max_ticks.load()) g_probe->max_ticks.store(ticks);
    }

    void writer_loop()
    {
        auto next_counts = std::chrono::steady_clock::now();
        while (g_probe->running.load())
        {
            std::vector<std::string> lines;
            {
                std::lock_guard guard(g_probe->mutex);
                lines.swap(g_probe->pending);
            }
            if (std::chrono::steady_clock::now() >= next_counts)
            {
                std::string counts = std::to_string(now_ms()) + " counts";
                for (size_t i = 0; i < WATCHED.size(); ++i)
                {
                    std::wstring name(WATCHED[i]);
                    counts += " " + narrow(name.substr(name.find(L':') + 1)) + "=" + std::to_string(g_probe->calls[i].load());
                }
                // Cumulative, so two lines can be differenced. Microseconds of the callback's own time.
                const double us = 1e6 / static_cast<double>(g_probe->tick_frequency);
                const uint64_t seen = g_probe->seen.load();
                char cost[200];
                std::snprintf(cost, sizeof cost, " | process_events=%llu callback_us_total=%.0f callback_us_mean=%.3f "
                              "callback_us_max=%.1f decode_log_us_total=%.0f", static_cast<unsigned long long>(seen),
                              g_probe->spent_ticks.load() * us, seen ? g_probe->spent_ticks.load() * us / seen : 0.0,
                              g_probe->max_ticks.load() * us, g_probe->matched_ticks.load() * us);
                counts += cost;
                lines.push_back(std::move(counts));
                next_counts = std::chrono::steady_clock::now() + std::chrono::seconds(10);
            }
            if (!lines.empty())
            {
                if (FILE* f = _wfopen(g_probe->path.c_str(), L"ab"))
                {
                    for (const auto& line : lines) { fwrite(line.data(), 1, line.size(), f); fputc('\n', f); }
                    fclose(f);
                }
            }
            Sleep(200);
        }
    }

    std::wstring log_path()
    {
        HMODULE module{};
        GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                           reinterpret_cast<LPCWSTR>(&log_path), &module);
        wchar_t buffer[MAX_PATH]{};
        GetModuleFileNameW(module, buffer, MAX_PATH);
        std::wstring path(buffer);
        // ...\Mods\BattleMetersNativeHits\dlls\main.dll -> ...\Mods\BattleMetersNativeHits\hits.log
        for (int up = 0; up < 2; ++up) path = path.substr(0, path.find_last_of(L"\\/"));
        return path + L"\\hits.log";
    }

    class Mod : public RC::CppUserModBase
    {
        std::thread writer;
    public:
        Mod()
        {
            ModName = STR("BattleMetersNativeHits");
            ModVersion = STR("0.1.0");
            ModAuthors = STR("Battle Meters");
            ModDescription = STR("Development probe: logs the game's per-hit events (issue 1)");
            g_probe = new Probe();
            g_probe->path = log_path();
            LARGE_INTEGER frequency{};
            QueryPerformanceFrequency(&frequency);
            g_probe->tick_frequency = frequency.QuadPart > 0 ? frequency.QuadPart : 1;
            queue(std::to_string(now_ms()) + " loaded");
            writer = std::thread(writer_loop);
        }

        void on_unreal_init() override
        {
            g_get_name_private = reinterpret_cast<GetNamePrivateFn>(GetProcAddress(
                GetModuleHandleW(L"UE4SS.dll"), "?GetNamePrivate@UObjectBase@Unreal@RC@@QEBAAEBVFName@23@XZ"));
            std::string resolved = std::to_string(now_ms()) + " resolved (name lookup " +
                (g_get_name_private ? "found" : "MISSING: nothing will match") + "):";
            for (size_t i = 0; i < WATCHED.size(); ++i)
            {
                auto* function = UObjectGlobals::StaticFindObject<UFunction*>(nullptr, nullptr, WATCHED[i]);
                g_probe->indexes[i] = name_index(function);
                resolved += " " + narrow(WATCHED[i]) + "=" + (function ? std::to_string(g_probe->indexes[i]) : "missing");
            }
            queue(std::move(resolved));
            Hook::RegisterProcessEventPreCallback(on_process_event);
        }

        ~Mod() override
        {
            g_probe->running.store(false);
            if (writer.joinable()) writer.join();
        }
    };
}

#define MOD_EXPORT __declspec(dllexport)
extern "C"
{
    MOD_EXPORT RC::CppUserModBase* start_mod() { return new BattleMetersNativeHits::Mod(); }
    MOD_EXPORT void uninstall_mod(RC::CppUserModBase* mod) { delete mod; }
}

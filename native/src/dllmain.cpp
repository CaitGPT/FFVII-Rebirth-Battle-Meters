// Battle Meters Native: the game's hit events for Battle Meters' damage and healing by character (issue 1).
//
// A UE4SS C++ mod, built for UE4SS 3.0.1. It changes nothing in the game. Lua RegisterHook on Blueprint overrides never
// fires in this game's UE4SS, but every call to the battle scene's OnTakeDamage still goes through UObject::ProcessEvent,
// which UE4SS hooks. This mod registers a ProcessEvent pre-callback once, at load (registering during play can crash),
// and for each call compares the called function's name index with OnTakeDamage's: one integer compare per call.
//
// A matching call's Damage, CauserCharaName, DamagedCharaName and bHeal are read at the offsets the game's own reflection
// gives and queued. Battle Meters' Lua side takes them with BattleMetersNativeHit() on its tick and matches them to the
// HP it reads, so a hit is never credited beyond the HP it really took or healed.
#include <Windows.h>
#include <Mod/CppUserModBase.hpp>
#include <LuaMadeSimple/LuaMadeSimple.hpp>
#include <Unreal/UObjectGlobals.hpp>
#include <Unreal/UObject.hpp>
#include <Unreal/UClass.hpp>
#include <Unreal/UFunction.hpp>
#include <Unreal/FProperty.hpp>
#include <Unreal/Property/FBoolProperty.hpp>
#include <Unreal/NameTypes.hpp>

#include <atomic>
#include <cstdint>
#include <deque>
#include <functional>
#include <mutex>
#include <string>
#include <unordered_map>

namespace RC::Unreal::Hook
{
    // Exact declaration from the installed UEPseudo (as the project's telemetry exporter uses it); the headers omit it.
    using ProcessEventCallback = std::function<void(UObject*, UFunction*, void*)>;
    RC_UE_API auto RegisterProcessEventPreCallback(ProcessEventCallback) -> void;
}

namespace BattleMetersNative
{
    using namespace RC::Unreal;

    constexpr const wchar_t* ON_TAKE_DAMAGE = L"/Script/EndGame.EndBattleSceneBlueprint:OnTakeDamage";
    constexpr size_t MAX_QUEUE = 2048;   // a long fight's worth between two Lua ticks many times over

    struct Hit
    {
        int32_t damage{};
        std::string causer;
        std::string target;
        bool heal{};
    };

    // Where OnTakeDamage's four values sit in one function's parameters. Each Blueprint override is its own UFunction,
    // so this is worked out once per function, from reflection, and the function is skipped if anything doesn't fit.
    struct Layout
    {
        bool usable{};
        int32_t damage{-1}, causer{-1}, target{-1}, heal{-1};
        FBoolProperty* heal_property{};
    };

    struct State
    {
        std::mutex mutex;
        std::deque<Hit> queue;
        uint64_t dropped{};                                    // oldest hits dropped because the queue was full
        std::atomic<uint64_t> total{};                         // hits queued since load
        std::unordered_map<UFunction*, Layout> layouts;        // game thread only
        uint32_t index{};                                      // OnTakeDamage's FName comparison index; 0 = not hooked
        std::string status{"not started"};
    };
    State* g_state{};

    // UObjectBase::GetNamePrivate() const, looked up by its exported name: the 3.0.1 headers declare FName as a struct
    // and UE4SS.dll exports it as a class, so the linker can't match the header. It returns a reference to the
    // object's FName, whose first 32 bits are the comparison index. Missing on another UE4SS build: then nothing hooks.
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
        for (wchar_t c : text) out.push_back(c >= 32 && c < 127 ? static_cast<char>(c) : '?');
        return out;
    }

    void set_status(std::string text)
    {
        std::lock_guard guard(g_state->mutex);
        g_state->status = std::move(text);
    }

    const Layout& layout_of(UFunction* function)
    {
        auto found = g_state->layouts.find(function);
        if (found != g_state->layouts.end()) return found->second;
        Layout layout{};
        for (FProperty* property : function->ForEachProperty())
        {
            const std::wstring name = property->GetName();
            const std::wstring type = property->GetClass().GetName();
            const int32_t offset = property->GetOffset_Internal();
            if (name == L"Damage" && type == L"IntProperty") layout.damage = offset;
            else if (name == L"CauserCharaName" && type == L"NameProperty") layout.causer = offset;
            else if (name == L"DamagedCharaName" && type == L"NameProperty") layout.target = offset;
            else if (name == L"bHeal" && type == L"BoolProperty")
            {
                layout.heal = offset;
                layout.heal_property = static_cast<FBoolProperty*>(property);
            }
        }
        layout.usable = layout.damage >= 0 && layout.causer >= 0 && layout.target >= 0 && layout.heal_property;
        if (!layout.usable) set_status("OnTakeDamage parameters not as expected in " + narrow(function->GetFullName()));
        return g_state->layouts.emplace(function, layout).first->second;
    }

    void on_process_event(UObject*, UFunction* function, void* parms)
    {
        if (!function || !parms || g_state->index == 0 || name_index(function) != g_state->index) return;
        const Layout& layout = layout_of(function);
        if (!layout.usable) return;
        auto* base = static_cast<uint8_t*>(parms);
        Hit hit{*reinterpret_cast<int32_t*>(base + layout.damage),
                narrow(reinterpret_cast<FName*>(base + layout.causer)->ToString()),
                narrow(reinterpret_cast<FName*>(base + layout.target)->ToString()),
                layout.heal_property->GetPropertyValue(base + layout.heal)};
        std::lock_guard guard(g_state->mutex);
        if (g_state->queue.size() >= MAX_QUEUE)
        {
            g_state->queue.pop_front();
            ++g_state->dropped;
        }
        g_state->queue.push_back(std::move(hit));
        ++g_state->total;
    }

    // BattleMetersNativeHit() -> damage, causer, target, heal for the oldest hit, or nothing once the queue is empty.
    int lua_hit(const RC::LuaMadeSimple::Lua& lua)
    {
        Hit hit;
        {
            std::lock_guard guard(g_state->mutex);
            if (g_state->queue.empty()) return 0;
            hit = std::move(g_state->queue.front());
            g_state->queue.pop_front();
        }
        lua.set_integer(hit.damage);
        lua.set_string(hit.causer);
        lua.set_string(hit.target);
        lua.set_bool(hit.heal);
        return 4;
    }

    // BattleMetersNativeStatus() -> status text ("ok" when hooked), hits dropped since the last call, hits since load.
    int lua_status(const RC::LuaMadeSimple::Lua& lua)
    {
        std::string status;
        uint64_t dropped{};
        {
            std::lock_guard guard(g_state->mutex);
            status = g_state->status;
            dropped = g_state->dropped;
            g_state->dropped = 0;
        }
        lua.set_string(status);
        lua.set_integer(static_cast<int64_t>(dropped));
        lua.set_integer(static_cast<int64_t>(g_state->total.load()));
        return 3;
    }

    class Mod : public RC::CppUserModBase
    {
    public:
        Mod()
        {
            ModName = STR("BattleMetersNative");
            ModVersion = STR("1.1.0");
            ModAuthors = STR("CaitGPT");
            ModDescription = STR("The game's hit events for Battle Meters' damage and healing by character");
            g_state = new State();
        }

        void on_unreal_init() override
        {
            g_get_name_private = reinterpret_cast<GetNamePrivateFn>(GetProcAddress(
                GetModuleHandleW(L"UE4SS.dll"), "?GetNamePrivate@UObjectBase@Unreal@RC@@QEBAAEBVFName@23@XZ"));
            if (!g_get_name_private)
            {
                set_status("this UE4SS build lacks the name lookup Battle Meters Native was built for (UE4SS 3.0.1)");
                return;
            }
            auto* function = UObjectGlobals::StaticFindObject<UFunction*>(nullptr, nullptr, ON_TAKE_DAMAGE);
            g_state->index = name_index(function);
            if (g_state->index == 0)
            {
                set_status("OnTakeDamage not found in this game build");
                return;
            }
            Hook::RegisterProcessEventPreCallback(on_process_event);
            set_status("ok");
        }

        // Battle Meters' Lua side starts after the C++ mods, so its functions are in place before its main.lua runs.
        void on_lua_start(StringViewType mod_name, RC::LuaMadeSimple::Lua& lua, RC::LuaMadeSimple::Lua&,
                          RC::LuaMadeSimple::Lua&, std::vector<RC::LuaMadeSimple::Lua*>&) override
        {
            if (mod_name != STR("BattleMeters")) return;
            lua.register_function("BattleMetersNativeHit", lua_hit);
            lua.register_function("BattleMetersNativeStatus", lua_status);
        }
    };
}

#define MOD_EXPORT __declspec(dllexport)
extern "C"
{
    MOD_EXPORT RC::CppUserModBase* start_mod() { return new BattleMetersNative::Mod(); }
    MOD_EXPORT void uninstall_mod(RC::CppUserModBase* mod) { delete mod; }
}

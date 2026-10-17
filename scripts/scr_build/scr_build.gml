/// scr_build
/// Which program this build is (docs/ENGINE_DESIGN.md §0):
///   Default config -> the Editor (what people make games with)
///   Player config  -> the Player (the runtime shipped with every exported game)
/// Engine scripts may read NTC64_EDITOR to stay out of the Player's way, but must
/// never call Editor scripts.

#macro NTC64_EDITOR true
#macro Player:NTC64_EDITOR false

#macro NTC64_VERSION "0.1.0"

/// Game pack format version. The Player loads every version up to this one.
#macro NTC64_PACK_VERSION 1

/// @desc "Editor" or "Player", for logs and the window caption.
function build_program_name()
{
    if (NTC64_EDITOR)
    {
        return "Editor";
    }
    return "Player";
}

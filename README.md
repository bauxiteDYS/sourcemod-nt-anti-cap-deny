# nt_anti_ghostcap_deny
A SourceMod plugin for Neotokyo which provides the following gameplay change:

*If the last living player of a team suicides (or gets posthumously teamkilled) to prevent a ghost capture, treat it as if the ghost capture happened.*

## Compile dependencies
* [SourceMod](https://www.sourcemod.net/) version 1.8 or newer (tested on version 1.10)
* [Neotokyo include](https://github.com/softashell/sourcemod-nt-include) for SourceMod

## ConVars
* *sm_nt_anti_ghost_cap_deny_sfx* - Whether to play sound FX on the cap deny event. (Default: 1)

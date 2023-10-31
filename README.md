# nt_anti_ghostcap_deny
A SourceMod plugin for Neotokyo which provides the following gameplay change:

*If the last living player of a team disconnects or suicides (or gets posthumously teamkilled) to prevent a ghost capture, treat it as if the ghost capture happened.*

## Compile dependencies
* [SourceMod](https://www.sourcemod.net/) version 1.8 or newer.
* [Neotokyo include](https://github.com/softashell/sourcemod-nt-include) for SourceMod

## ConVars
* sm_nt_anti_ghost_cap_deny_version
  * Default value: `PLUGIN_VERSION`
  * Description: `NEOTOKYO° Anti Ghost Cap Deny plugin version.`
  * Bit flags: `FCVAR_DONTRECORD`
* sm_nt_anti_ghost_cap_deny_sfx
  * Default value: `1`
  * Description: `Whether to play sound FX on the cap deny event.`


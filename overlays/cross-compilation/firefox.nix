(final: prev: {
   # Bug which prevent cross-compilation applied upstream, should be avaliable in 121 or 122
   # Temporary revert to firefox-esr (aka 115)
   firefox = if prev.firefox.version == "120.0" then prev.firefox-esr else prev.firefox;
})

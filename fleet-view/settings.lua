data:extend({
  {
    type = "bool-setting",
    name = "fleet-view-detail",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "a",
  },
  {
    type = "bool-setting",
    name = "fleet-view-float",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "b",
  },
  {
    type = "string-setting",
    -- 0.5.0: renamed from fleet-view-float-smoothness WITH the default change balanced -> smooth. A changed default does
    -- not reach existing installs: the old value stays stored in the save AND in each install's mod-settings.dat, even
    -- for players who never touched it (probed 2026-11-16 with a server run). A new name has no stored value anywhere.
    name = "fleet-view-smoothness",
    setting_type = "runtime-per-user",
    default_value = "smooth",   -- 0.5.0 (owner 2026-11-16): floor blocks made it cheap enough; was "balanced" (0.4.9-0.4.11)
    allowed_values = { "smooth", "balanced", "light" },
    order = "c",
  },
  {
    type = "string-setting",
    name = "fleet-view-parallax",
    setting_type = "runtime-per-user",
    default_value = "off",   -- opt-in: the game reports no camera moves during a remote-view drag, so ships jump after it (owner 2026-11-12)
    allowed_values = { "off", "subtle", "medium", "strong" },
    order = "d",
  },
  {
    type = "bool-setting",
    name = "fleet-view-zoom-transfer",
    setting_type = "runtime-per-user",
    default_value = false,   -- opt-in (owner 2026-11-12)
    order = "e",
  },
})

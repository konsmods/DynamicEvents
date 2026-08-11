if not SandboxVars then SandboxVars = {} end

SandboxVars.DynamicEvents = {
    Enabled              = true,
    MaxActiveEvents      = 10,
    MinHoursBetweenEvents = 1.0,
    EventChance          = 100, --50
    GracePeriodHours     = 1.0,
    EventCleanup         = true,
    MinDistanceBetweenEvents = 20,
    Debug                = false,

    EventToggles = {
        heli_crash       = false,
        train_wreck      = false,
        convoy_crash     = false,
        convoy_crash_ki5 = true,
        example_event    = false,
    },
}

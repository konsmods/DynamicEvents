if not SandboxVars then SandboxVars = {} end

SandboxVars.DynamicEvents = {
    Enabled              = true,
    MaxActiveEvents      = 3,
    MinHoursBetweenEvents = 1.0,
    EventChance          = 50,
    GracePeriodHours     = 0,
    EventCleanup         = true,
    MinDistanceBetweenEvents = 20,
    MinDistanceFromVehicles  = 15,
    Debug                = false,

    EventToggles = {
        heli_crash       = true,
        train_wreck      = true,
        convoy_crash     = true,
        convoy_crash_ki5 = true,
        example_event    = false,
    },
}

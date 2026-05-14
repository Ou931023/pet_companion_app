import 'platform_liquid_glass_stub.dart'
    if (dart.library.io) 'platform_liquid_glass_io.dart';

bool get supportsLiquidGlassHomeBar => isIos26OrNewer();

import Toybox.WatchUi;
import Toybox.Lang;

// Maps a WMO weather code + is_day flag to a loaded BitmapResource.
// wmoIcon()   → 44×44 version (current conditions page, glance)
// wmoIconSm() → 22×22 version (forecast daily rows)
// Icon set: Met.no weathericons, sourced from BleachDev/Rainy (GPL-3.0).
//
// WMO codes used by Open-Meteo:
//   0        Clear sky
//   1/2/3    Mainly clear / partly cloudy / overcast
//   45/48    Fog / rime fog
//   51/53/55 Drizzle light/moderate/dense
//   61/63/65 Rain light/moderate/heavy
//   71/73/75 Snow light/moderate/heavy
//   77       Snow grains
//   80/81/82 Rain showers light/moderate/heavy
//   85/86    Snow showers light/heavy
//   95       Thunderstorm
//   96/99    Thunderstorm with hail
function wmoIcon(code as Number, isDay as Boolean) as WatchUi.BitmapResource {
    var id = isDay ? Rez.Drawables.clearsky_day : Rez.Drawables.clearsky_night;
    if      (code == 1)                                        { id = isDay ? Rez.Drawables.fair_day              : Rez.Drawables.fair_night; }
    else if (code == 2)                                        { id = isDay ? Rez.Drawables.partlycloudy_day      : Rez.Drawables.partlycloudy_night; }
    else if (code == 3)                                        { id = Rez.Drawables.cloudy; }
    else if (code == 45 || code == 48)                         { id = Rez.Drawables.fog; }
    else if (code == 51 || code == 53 || code == 55 || code == 61) { id = Rez.Drawables.lightrain; }
    else if (code == 63)                                       { id = Rez.Drawables.rain; }
    else if (code == 65)                                       { id = Rez.Drawables.heavyrain; }
    else if (code == 71 || code == 77)                         { id = Rez.Drawables.lightsnow; }
    else if (code == 73)                                       { id = Rez.Drawables.snow; }
    else if (code == 75)                                       { id = Rez.Drawables.heavysnow; }
    else if (code == 80)                                       { id = isDay ? Rez.Drawables.lightrainshowers_day  : Rez.Drawables.lightrainshowers_night; }
    else if (code == 81)                                       { id = isDay ? Rez.Drawables.rainshowers_day       : Rez.Drawables.rainshowers_night; }
    else if (code == 82)                                       { id = isDay ? Rez.Drawables.heavyrainshowers_day  : Rez.Drawables.heavyrainshowers_night; }
    else if (code == 85)                                       { id = Rez.Drawables.snow; }
    else if (code == 86)                                       { id = Rez.Drawables.heavysnow; }
    else if (code == 95)                                       { id = Rez.Drawables.rainandthunder; }
    else if (code == 96 || code == 99)                         { id = Rez.Drawables.heavyrainandthunder; }
    return WatchUi.loadResource(id) as WatchUi.BitmapResource;
}

(:glance)
function wmoIconSm(code as Number, isDay as Boolean) as WatchUi.BitmapResource {
    var id = isDay ? Rez.Drawables.clearsky_day_sm : Rez.Drawables.clearsky_night_sm;
    if      (code == 1)                                        { id = isDay ? Rez.Drawables.fair_day_sm              : Rez.Drawables.fair_night_sm; }
    else if (code == 2)                                        { id = isDay ? Rez.Drawables.partlycloudy_day_sm      : Rez.Drawables.partlycloudy_night_sm; }
    else if (code == 3)                                        { id = Rez.Drawables.cloudy_sm; }
    else if (code == 45 || code == 48)                         { id = Rez.Drawables.fog_sm; }
    else if (code == 51 || code == 53 || code == 55 || code == 61) { id = Rez.Drawables.lightrain_sm; }
    else if (code == 63)                                       { id = Rez.Drawables.rain_sm; }
    else if (code == 65)                                       { id = Rez.Drawables.heavyrain_sm; }
    else if (code == 71 || code == 77)                         { id = Rez.Drawables.lightsnow_sm; }
    else if (code == 73)                                       { id = Rez.Drawables.snow_sm; }
    else if (code == 75)                                       { id = Rez.Drawables.heavysnow_sm; }
    else if (code == 80)                                       { id = isDay ? Rez.Drawables.lightrainshowers_day_sm  : Rez.Drawables.lightrainshowers_night_sm; }
    else if (code == 81)                                       { id = isDay ? Rez.Drawables.rainshowers_day_sm       : Rez.Drawables.rainshowers_night_sm; }
    else if (code == 82)                                       { id = isDay ? Rez.Drawables.heavyrainshowers_day_sm  : Rez.Drawables.heavyrainshowers_night_sm; }
    else if (code == 85)                                       { id = Rez.Drawables.snow_sm; }
    else if (code == 86)                                       { id = Rez.Drawables.heavysnow_sm; }
    else if (code == 95)                                       { id = Rez.Drawables.rainandthunder_sm; }
    else if (code == 96 || code == 99)                         { id = Rez.Drawables.heavyrainandthunder_sm; }
    return WatchUi.loadResource(id) as WatchUi.BitmapResource;
}

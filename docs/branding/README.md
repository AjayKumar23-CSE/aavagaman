# BlinCab brand assets (D-059)

Name: **BlinCab** — tagline **Bike • Cab • Auto**. The logo is the owner's: yellow and white
line art of an auto, a cab and a bike on black (`blincab-logo-source.png`, 1254 px).

| Colour | Hex | Use |
|---|---|---|
| Taxi yellow | `#FFD714` | the cab, "Cab" in the wordmark, dark-mode primary, pins, loaders |
| Amber | `#C99A00` | yellow that reads on white: admin accents, the driver app's primary (`#8A6500`) |
| Black | `#0A0A0A` | logo background, launch screen, icon tiles, rider primary (`#141414`) |
| Grey | `#BDBDBD` | the tagline |
| Road | `#1F1F1F` | the road strip under the vehicles |

Files:

- `blincab-logo-source.png`: the logo as supplied (opaque black background).
- `blincab-vehicles.png` (1010×440): the three vehicles with the black made transparent, also
  shipped as `apps/shared/assets/blincab_vehicles.png`. This is the mark: app icons, launch
  screen, admin panel, and the splash and login header, where the name "BlinCab" and the tagline
  are set in code next to it (the owner's choice: no text inside the icon).
- `blincab-logo.png` (985×715): the full lock-up with text, transparent, for print and stores.
- `icon-rider-512.png` / `icon-driver-512.png`: Play Store icons (the vehicles on a black tile;
  the driver's has a yellow rim so the two apps tell apart on one phone). `blincab-tile-1024.png`
  is the plain tile.
- `splash-1080x2400.png` and `splash-looks.png`: the shipped splash and the five looks compared.
- `splash-india-gate-source.png`: the India Gate picture behind the splash (sunk to night, D-059).

The admin panel's `admin/public/logo.png` is the 192 px tile. Regenerate everything from the
cut-out with `RIDE_BRAND_OUT=<dir> flutter test --update-goldens test/branding` in `apps/shared`,
then copy the `*-ic_launcher-*`, `*-ic_launcher_foreground-*` and `*-launch_logo-*` files into the
apps' `mipmap-*` folders.

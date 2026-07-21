#!/usr/bin/env bash
# Downloads the 6 Taj AR target images (Wikimedia Commons, free licenses)
# into backend/targets/, named to match targetImageId in content/taj_mahal.yaml.
# Run on the Mac:  bash fetch_targets.sh
# IMPORTANT: the SAME files get (a) registered as ARKit reference images in the
# app bundle and (b) printed as the physical demo targets. Print from these
# exact files or tracking will degrade.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p targets

fp() { # fp <targetImageId> <Commons file name (URL-encoded)>
  local out="targets/$1.jpg"
  local url="https://commons.wikimedia.org/wiki/Special:FilePath/$2?width=2400"
  echo "-> $1"
  curl -fsSL "$url" -o "$out"
  local size
  size=$(stat -f%z "$out" 2>/dev/null || stat -c%s "$out")
  if [ "$size" -lt 100000 ]; then
    echo "   WARN: $out is only $size bytes — open and verify manually"
  else
    echo "   ok ($((size/1024)) KB)"
  fi
}

fp taj_great_gate       "Great_gate_(Darwaza-i_rauza)_is_the_main_entrance_to_the_tomb,_Taj_Mahal.jpg"
fp taj_gate_calligraphy "Taj_Mahal_gate-5.jpg"
fp taj_marble_closeup   "TajJaliInlay.jpg"
fp taj_minaret          "The_Taj_with_its_minaret.JPG"
fp taj_pietra_dura      "A_pietra_dura_panel_from_the_Taj_Mahal_(6125141438).jpg"
fp taj_river_terrace    "Taj_Majal_y_rio_Yamuna.JPG"

echo
echo "Open each file and check: sharp, feature-rich, no heavy sky area."
echo "Then: python package_builder.py --content content/taj_mahal.yaml  (re-zips with targets)"
echo "Print at A4, matte if possible (glossy = glare = tracking loss)."

/// Which countries ship a flag-map, and which Wikimedia file each came from.
///
/// CURATED, NOT GENERATED. Every line was reviewed by hand and belongs in a
/// diff: the source folder is a scraped grab bag, and a name-matching
/// heuristic silently produced four wrong answers on its first run —
/// Mali from "So-MALI-land", Oman from "S-o-T-OM-AN-d and Principe",
/// Slovakia from "Czecho-SLOVAKIA", plus Western Sahara from a Moroccan
/// claim map. Three of those four were files that must never ship.
///
/// The rule this list encodes is binary and has no exceptions: a clean
/// sovereign-state map gets a flag-map, anything else gets the Natural Earth
/// silhouette from `country_shapes.g.dart`. Deliberately excluded, and not to
/// be re-added without a decision: irredentist maps (Greater Israel, Greater
/// Albania, Greater Bulgaria, Greater Yemen, Greater Romania), disputed
/// territory (Western Sahara, Kurdistan, Somaliland, Mandatory Palestine,
/// Cyprus-without-TRNC, India de-facto, the Ukraine March-2022 snapshot),
/// defunct states (Czechoslovakia, British India, Belgian Congo, Austrian
/// Empire, Confederate States), and every sub-national and multi-country map.
///
/// The comment on each line is the ORIGINAL filename, so any entry can be
/// traced back to what it was cut from.
///
/// SIXTEEN further countries were cut after looking at the rendered cards:
/// Adobe Illustrator exports that wrap their fills in `<mask>` and
/// `<filter id="Adobe_OpacityMaskFilter">`, which flutter_svg does not
/// implement — Austria and Brunei drew as a bare, almost invisible outline on
/// device while Azerbaijan and Belgium beside them were perfect. Two more
/// (Armenia, Morocco) carry no colour at all. They fall back to the
/// silhouette like any other country without a map. A `<style>` block is NOT
/// disqualifying: Azerbaijan has one and renders correctly.
library;

/// Alpha-2 codes with a bundled flag-map at `assets/flag_maps/<code>.svg`.
const Map<String, String> kFlagMapSources = <String, String>{
  'af': 'Afghanistan_Flag_Map.svg', // Afghanistan
  'dz': 'Flag_and_map_of_Algeria.svg', // Algeria
  'ad': 'Flag_map_of_Andorra.svg', // Andorra
  'ao': 'Angola_Flag_Map.svg', // Angola
  'ar': 'Flag_map_of_Argentina.svg', // Argentina
  'au': 'Flag-map_of_Australia.svg', // Australia
  'az': 'Flag_map_of_Azerbaijan_with_Baku_and_Lankaran.svg', // Azerbaijan
  'bd': 'Bangladesh_Map_Flag.svg', // Bangladesh
  'be': 'Flag_and_map_of_Belgium.svg', // Belgium
  'bz': 'Flag-map_of_Belize.svg', // Belize
  'bj': 'Flag_map_of_Benin.svg', // Benin
  'bt': 'Bhutan_Map_Flag.svg', // Bhutan
  'bo': 'Bolivia.svg', // Bolivia
  'bw': 'Flag_map_of_Botswana.svg', // Botswana
  'br': 'Flag-map_of_Brazil.svg', // Brazil
  'bf': 'Flag_map_of_Burkina_Faso.svg', // Burkina Faso
  'cm': 'Flag_map_of_Cameroon.svg', // Cameroon
  'ca': 'Flag_map_of_Canada.svg', // Canada
  'cf': 'Flag_map_of_the_Central_African_Republic.svg', // Central African Republic
  'td': 'Flag_map_of_Chad.svg', // Chad
  'co': 'Flag-map_of_Colombia.svg', // Colombia
  'km': 'Flag_map_of_the_Comoros.svg', // Comoros
  'cr': 'Flag-Map_Of_Costa_Rica.svg', // Costa Rica
  'cy': 'Flag_map_of_Cyprus.svg', // Cyprus
  'dj': 'Flag_map_of_Djibouti.svg', // Djibouti
  'do': 'Flag_map_of_the_Dominican_Republic.svg', // Dominican Republic
  'ec': 'Flag-map_of_Ecuador.svg', // Ecuador
  'eg': 'Flag-map_of_Egypt.svg', // Egypt
  'gq': 'Flag_map_of_Equatorial_Guinea.svg', // Equatorial Guinea
  'er': 'Flag-map_of_Eritrea.svg', // Eritrea
  'et': 'Flag_map_of_Ethiopia.svg', // Ethiopia
  'fr': 'Flag_map_of_France.svg', // France
  'ga': 'Flag_map_of_Gabon.svg', // Gabon
  'gm': 'Flag_map_of_The_Gambia.svg', // Gambia
  'de': 'Flag_map_of_Germany.svg', // Germany
  'gh': 'Flag_map_of_Ghana.svg', // Ghana
  'gr': 'Flag-map_of_Greece2.svg', // Greece
  'gt': 'Flag_map_of_Guatemala.svg', // Guatemala
  'gn': 'Flag_map_of_Guinea.svg', // Guinea
  'gw': 'Flag_map_of_Guinea-Bissau.svg', // Guinea-Bissau
  'gy': 'Flag-map_of_Guyana.svg', // Guyana
  'ht': 'Flag_map_of_Haiti.svg', // Haiti
  'hu': 'Flag-map_of_Hungary.svg', // Hungary
  'ir': 'F_iran.svg', // Iran
  'ie': 'Flag-map_of_Ireland.svg', // Ireland
  'jp': 'Flag_and_map_of_Japan.svg', // Japan
  'jo': 'Flag_and_map_of_Jordan.svg', // Jordan
  'kz': 'Flag_map_of_Kazakhstan.svg', // Kazakhstan
  'ke': 'Flag_map_of_Kenya.svg', // Kenya
  'lb': 'Flag-map_of_Lebanon.svg', // Lebanon
  'ls': 'Flag_map_of_Lesotho.svg', // Lesotho
  'ly': 'Flag_Map_of_Libya.svg', // Libya
  'mg': 'Flag_map_of_Madagascar.svg', // Madagascar
  'mw': 'Flag_map_of_Malawi.svg', // Malawi
  'mt': 'Flag_map_of_Malta.svg', // Malta
  'mc': 'Flag_map_of_Monaco.svg', // Monaco
  'na': 'Flag_map_of_Namibia.svg', // Namibia
  'nz': 'Flag_and_map_of_New Zealand.svg', // New Zealand
  'ne': 'Flag_map_of_Niger.svg', // Niger
  'no': 'Flag_map_of_Norway.svg', // Norway
  'pa': 'Flag-map_of_Panama.svg', // Panama
  'py': 'Flag-map_of_Paraguay.svg', // Paraguay
  'ph': 'Flag_map_of_the_Philippines.svg', // Philippines
  'rw': 'Flag_map_of_Rwanda.svg', // Rwanda
  'sm': 'Flag_map_of_San_Marino.svg', // San Marino
  'sa': 'Saudi_Arabia-Flagmap.svg', // Saudi Arabia
  'sn': 'Flag_map_of_Senegal.svg', // Senegal
  'ss': 'Flag_map_of_South_Sudan.svg', // South Sudan
  'sr': 'Flag_Map_of_Suriname.svg', // Suriname
  'ug': 'Flag_map_of_Uganda.svg', // Uganda
  'uz': 'Flag_and_map_of_Uzbekistan.svg', // Uzbekistan
  'vn': 'Flag_map_of_Vietnam.svg', // Vietnam
  'zm': 'Flag_map_of_Zambia.svg', // Zambia
  'zw': 'Flag_map_of_Zimbabwe.svg', // Zimbabwe
};

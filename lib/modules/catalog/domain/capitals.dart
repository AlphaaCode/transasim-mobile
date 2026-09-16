/// Capital cities, so that typing "Paris" finds France.
///
/// Bundled, static, one entry per country the live `/v1/countries/all` returns
/// (246), keyed by the ISO 3166-1 alpha-3 code the catalogue already joins on.
/// No backend involvement: capitals do not change often enough to need one.
///
/// Scope is capitals and nothing else. "Major cities" is a different problem
/// with no natural cutoff, and it is deliberately not started here.
///
/// Where a country's capital is genuinely split or commonly named two ways,
/// both are listed (`|`), because a traveller types the one they know:
/// Bolivia, Côte d'Ivoire, Eswatini, South Africa, Sri Lanka, Ukraine
/// (Kyiv/Kiev), Montserrat, Palestine. ⚠️ Palestine lists Jerusalem and
/// Ramallah, and Western Sahara lists Laayoune; both are disputed, and whether
/// to list them is a product call, made in this one place.
///
/// Omitted because there is no capital to type: Antarctica, Bouvet Island,
/// Heard and McDonald Islands, US Minor Outlying Islands, Tokelau.
///
/// Names here are the English exonyms. Other languages' names for the same
/// capitals come from Wikidata, in place_names.g.dart, checked against this
/// table; see destination_search.dart.
library;

export '../../../core/i18n/fold.dart' show foldForSearch;

/// The capital name(s) for [iso3], empty when there is none.
List<String> capitalsOf(String iso3) => _capitals[iso3.toUpperCase()]?.split('|') ?? const [];

/// Every country the curated table covers.
Iterable<String> get capitalCountryCodes => _capitals.keys;

const Map<String, String> _capitals = {
  'ABW': 'Oranjestad', 'AFG': 'Kabul', 'AGO': 'Luanda', 'AIA': 'The Valley',
  'ALA': 'Mariehamn', 'ALB': 'Tirana', 'AND': 'Andorra la Vella', 'ARE': 'Abu Dhabi',
  'ARG': 'Buenos Aires', 'ARM': 'Yerevan', 'ASM': 'Pago Pago', 'ATF': 'Port-aux-Français',
  'ATG': "Saint John's", 'AUS': 'Canberra', 'AUT': 'Vienna', 'AZE': 'Baku',
  'BDI': 'Gitega', 'BEL': 'Brussels', 'BEN': 'Porto-Novo', 'BES': 'Kralendijk',
  'BFA': 'Ouagadougou', 'BGD': 'Dhaka', 'BGR': 'Sofia', 'BHR': 'Manama',
  'BHS': 'Nassau', 'BIH': 'Sarajevo', 'BLM': 'Gustavia', 'BLR': 'Minsk',
  'BLZ': 'Belmopan', 'BMU': 'Hamilton', 'BOL': 'Sucre|La Paz', 'BRA': 'Brasília',
  'BRB': 'Bridgetown', 'BRN': 'Bandar Seri Begawan', 'BTN': 'Thimphu', 'BWA': 'Gaborone',
  'CAF': 'Bangui', 'CAN': 'Ottawa', 'CCK': 'West Island', 'CHE': 'Bern',
  'CHL': 'Santiago', 'CHN': 'Beijing', 'CIV': 'Yamoussoukro|Abidjan', 'CMR': 'Yaoundé',
  'COD': 'Kinshasa', 'COG': 'Brazzaville', 'COK': 'Avarua', 'COL': 'Bogotá',
  'COM': 'Moroni', 'CPV': 'Praia', 'CRI': 'San José', 'CUB': 'Havana',
  'CUW': 'Willemstad', 'CXR': 'Flying Fish Cove', 'CYM': 'George Town', 'CYP': 'Nicosia',
  'CZE': 'Prague', 'DEU': 'Berlin', 'DJI': 'Djibouti', 'DMA': 'Roseau',
  'DNK': 'Copenhagen', 'DOM': 'Santo Domingo', 'DZA': 'Algiers', 'ECU': 'Quito',
  'EGY': 'Cairo', 'ERI': 'Asmara', 'ESH': 'Laayoune', 'ESP': 'Madrid',
  'EST': 'Tallinn', 'ETH': 'Addis Ababa', 'FIN': 'Helsinki', 'FJI': 'Suva',
  'FLK': 'Stanley', 'FRA': 'Paris', 'FRO': 'Tórshavn', 'FSM': 'Palikir',
  'GAB': 'Libreville', 'GBR': 'London', 'GEO': 'Tbilisi', 'GGY': 'Saint Peter Port',
  'GHA': 'Accra', 'GIB': 'Gibraltar', 'GIN': 'Conakry', 'GLP': 'Basse-Terre',
  'GMB': 'Banjul', 'GNQ': 'Malabo', 'GRC': 'Athens', 'GRD': "Saint George's",
  'GRL': 'Nuuk', 'GTM': 'Guatemala City', 'GUF': 'Cayenne', 'GUM': 'Hagåtña',
  'GUY': 'Georgetown', 'HKG': 'Hong Kong', 'HND': 'Tegucigalpa', 'HRV': 'Zagreb',
  'HTI': 'Port-au-Prince', 'HUN': 'Budapest', 'IDN': 'Jakarta', 'IMN': 'Douglas',
  'IND': 'New Delhi', 'IOT': 'Diego Garcia', 'IRL': 'Dublin', 'IRN': 'Tehran',
  'IRQ': 'Baghdad', 'ISL': 'Reykjavík', 'ITA': 'Rome', 'JAM': 'Kingston',
  'JEY': 'Saint Helier', 'JOR': 'Amman', 'JPN': 'Tokyo', 'KAZ': 'Astana',
  'KEN': 'Nairobi', 'KGZ': 'Bishkek', 'KHM': 'Phnom Penh', 'KIR': 'Tarawa',
  'KNA': 'Basseterre', 'KOR': 'Seoul', 'KWT': 'Kuwait City', 'LAO': 'Vientiane',
  'LBN': 'Beirut', 'LBR': 'Monrovia', 'LBY': 'Tripoli', 'LCA': 'Castries',
  'LIE': 'Vaduz', 'LKA': 'Sri Jayawardenepura Kotte|Colombo', 'LSO': 'Maseru', 'LTU': 'Vilnius',
  'LUX': 'Luxembourg', 'LVA': 'Riga', 'MAC': 'Macau', 'MAF': 'Marigot',
  'MAR': 'Rabat', 'MCO': 'Monaco', 'MDA': 'Chișinău', 'MDG': 'Antananarivo',
  'MDV': 'Malé', 'MEX': 'Mexico City', 'MHL': 'Majuro', 'MKD': 'Skopje',
  'MLI': 'Bamako', 'MLT': 'Valletta', 'MMR': 'Naypyidaw', 'MNE': 'Podgorica',
  'MNG': 'Ulaanbaatar', 'MNP': 'Saipan', 'MOZ': 'Maputo', 'MRT': 'Nouakchott',
  'MSR': 'Brades|Plymouth', 'MTQ': 'Fort-de-France', 'MUS': 'Port Louis', 'MWI': 'Lilongwe',
  'MYS': 'Kuala Lumpur', 'MYT': 'Mamoudzou', 'NAM': 'Windhoek', 'NCL': 'Nouméa',
  'NER': 'Niamey', 'NFK': 'Kingston', 'NGA': 'Abuja', 'NIC': 'Managua',
  'NIU': 'Alofi', 'NLD': 'Amsterdam', 'NOR': 'Oslo', 'NPL': 'Kathmandu',
  'NRU': 'Yaren', 'NZL': 'Wellington', 'OMN': 'Muscat', 'PAK': 'Islamabad',
  'PAN': 'Panama City', 'PCN': 'Adamstown', 'PER': 'Lima', 'PHL': 'Manila',
  'PLW': 'Ngerulmud', 'PNG': 'Port Moresby', 'POL': 'Warsaw', 'PRI': 'San Juan',
  'PRK': 'Pyongyang', 'PRT': 'Lisbon', 'PRY': 'Asunción', 'PSE': 'Jerusalem|Ramallah',
  'PYF': 'Papeete', 'QAT': 'Doha', 'REU': 'Saint-Denis', 'ROU': 'Bucharest',
  'RUS': 'Moscow', 'RWA': 'Kigali', 'SAU': 'Riyadh', 'SDN': 'Khartoum',
  'SEN': 'Dakar', 'SGP': 'Singapore', 'SGS': 'King Edward Point', 'SHN': 'Jamestown',
  'SJM': 'Longyearbyen', 'SLB': 'Honiara', 'SLE': 'Freetown', 'SLV': 'San Salvador',
  'SMR': 'San Marino', 'SOM': 'Mogadishu', 'SPM': 'Saint-Pierre', 'SRB': 'Belgrade',
  'SSD': 'Juba', 'STP': 'São Tomé', 'SUR': 'Paramaribo', 'SVK': 'Bratislava',
  'SVN': 'Ljubljana', 'SWE': 'Stockholm', 'SWZ': 'Mbabane|Lobamba', 'SXM': 'Philipsburg',
  'SYC': 'Victoria', 'SYR': 'Damascus', 'TCA': 'Cockburn Town', 'TCD': "N'Djamena",
  'THA': 'Bangkok', 'TJK': 'Dushanbe', 'TKM': 'Ashgabat', 'TLS': 'Dili',
  'TON': 'Nukuʻalofa', 'TUN': 'Tunis', 'TUR': 'Ankara', 'TUV': 'Funafuti',
  'TWN': 'Taipei', 'TZA': 'Dodoma', 'UGA': 'Kampala', 'UKR': 'Kyiv|Kiev',
  'URY': 'Montevideo', 'USA': 'Washington', 'UZB': 'Tashkent', 'VAT': 'Vatican City',
  'VCT': 'Kingstown', 'VEN': 'Caracas', 'VGB': 'Road Town', 'VIR': 'Charlotte Amalie',
  'VNM': 'Hanoi', 'VUT': 'Port Vila', 'WLF': 'Mata-Utu', 'WSM': 'Apia',
  'XKX': 'Pristina', 'YEM': "Sana'a", 'ZAF': 'Pretoria|Cape Town', 'ZMB': 'Lusaka',
  'ZWE': 'Harare',
};

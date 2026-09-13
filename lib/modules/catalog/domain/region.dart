/// Which part of the world a destination is in.
///
/// The backend has no notion of region: `/v1/countries/all` carries `id`,
/// `country`, `code`, `language`, `selected` and `currencies`, nothing else. So
/// the store's region filter is keyed off the ISO 3166-1 alpha-3 code the
/// catalogue already joins on, against the UN M49 geoscheme — a published
/// standard rather than a list someone would have to defend line by line.
///
/// One deliberate departure: Cyprus is M49 Western Asia, but it is an EU member
/// state inside EU roaming rules, and a traveller filtering "Europe" expects
/// it there. Other transcontinental cases (Türkiye, Georgia, Armenia,
/// Azerbaijan, Russia) follow M49 as written. Which bucket a country sits in is
/// a product call; this file is the one place to make it.
///
/// A code this table does not know has no region: it stays visible under
/// "All" and appears under no other chip, rather than being guessed into one.
library;

enum Region { europe, asia, americas, africa, oceania }

/// The chip order: the White-Label Store Template's three (66:54), then the
/// regions it did not draw, which the live catalogue nonetheless sells.
const List<Region> kRegionOrder = [
  Region.europe,
  Region.asia,
  Region.americas,
  Region.africa,
  Region.oceania,
];

Region? regionOf(String iso3) => _byCode[iso3.toUpperCase()];

final Map<String, Region> _byCode = {
  for (final entry in _members.entries)
    for (final code in entry.value.split(RegExp(r'\s+')).where((c) => c.isNotEmpty))
      code: entry.key,
};

const Map<Region, String> _members = {
  Region.europe: '''
    ALA ALB AND AUT BEL BGR BIH BLR CHE CYP CZE DEU DNK ESP EST FIN FRA FRO GBR
    GGY GIB GRC HRV HUN IMN IRL ISL ITA JEY LIE LTU LUX LVA MCO MDA MKD MLT MNE
    NLD NOR POL PRT ROU RUS SJM SMR SRB SVK SVN SWE UKR VAT XKX''',
  Region.asia: '''
    AFG ARE ARM AZE BGD BHR BRN BTN CHN GEO HKG IDN IND IRN IRQ ISR JOR JPN KAZ
    KGZ KHM KOR KWT LAO LBN LKA MAC MDV MMR MNG MYS NPL OMN PAK PHL PRK PSE QAT
    SAU SGP SYR THA TJK TKM TLS TUR TWN UZB VNM YEM''',
  Region.americas: '''
    ABW AIA ARG ATG BES BHS BLM BLZ BMU BOL BRA BRB BVT CAN CHL COL CRI CUB CUW
    CYM DMA DOM ECU FLK GLP GRD GRL GTM GUF GUY HND HTI JAM KNA LCA MAF MEX MSR
    MTQ NIC PAN PER PRI PRY SGS SLV SPM SUR SXM TCA TTO URY USA VCT VEN VGB VIR''',
  Region.africa: '''
    AGO ATF BDI BEN BFA BWA CAF CIV CMR COD COG COM CPV DJI DZA EGY ERI ESH ETH
    GAB GHA GIN GMB GNB GNQ IOT KEN LBR LBY LSO MAR MDG MLI MOZ MRT MUS MWI MYT
    NAM NER NGA REU RWA SDN SEN SHN SLE SOM SSD STP SWZ SYC TCD TGO TUN TZA UGA
    ZAF ZMB ZWE''',
  Region.oceania: '''
    ASM AUS CCK COK CXR FJI FSM GUM HMD KIR MHL MNP NCL NFK NIU NRU NZL PCN PLW
    PNG PYF SLB TKL TON TUV UMI VUT WLF WSM''',
};

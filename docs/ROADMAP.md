# Prior roadmap

_Last updated 2026-10-30._

Prior answers one question for agents, buyers and landowners: **"What water comes
with this land?"** Today it works in Utah and Colorado. Expanding to more states
matters more than anything else on this list. Most of the rural West is in
states where a buyer has no easy way to see this.

## Where it stands (v1.0.5)

| Area | Utah | Colorado |
|---|---|---|
| Parcel boundaries | UGRC ArcGIS, fetched live per view | Self-hosted PMTiles (R2 + Worker at `auaha.app/tiles/co`) |
| Parcel attributes | UGRC + county LIR services | Read from the rendered vector tile (instant) |
| Water rights | Utah POD layer + `wrprint` change applications | CDSS REST `structures` API |
| Extras | Utah Water Hub listings by area | none |
| PLSS | BLM national CadNSDI | BLM national CadNSDI |

- **Search:** address (Mapbox geocoding), parcel number, Utah water right number, or tap the map.
- **Basemaps:** Standard, Satellite, Satellite Streets, Outdoors, Dark.
- **Paywall:** 5 free lookups a month, then RevenueCat "Pro" for unlimited.
- **Gaps:** Saved Lookups is a placeholder screen. State detection is a bounding box. All the per-state logic sits in one 830-line `water_rights_client.dart`.

---

## Phase 1: Make adding a state cheap (refactor, about 1 week)

Every new state needs the same five pieces, so they become a pattern rather than
more branches in one file.

1. **A `StateSource` interface** in `lib/core/states/` (one file per state):
   ```dart
   abstract class StateSource {
     String get code;                     // 'UT'
     bool contains(double lat, double lng);
     Future<ParcelInfo?> parcelAt(double lat, double lng);
     Future<List<WaterRight>> waterRightsNear(double lat, double lng, {ParcelInfo? parcel});
     Future<(double, double)?> parcelCenter(String parcelId);   // parcel-number search
     ParcelTiles? get tiles;              // vector tiles, or null for live ArcGIS
     Uri? sourceRecordUrl(WaterRight r);  // "view official record" link
   }
   ```
   Move Utah and Colorado into `utah_source.dart` and `colorado_source.dart`.
   `WaterRightsClient` becomes a thin dispatcher over a registry.
2. **State detection by polygon**, not bbox. Ship simplified state outlines as one small GeoJSON asset (around 50 KB), or look the state up from Mapbox reverse geocoding, which we already call.
3. **A normalized `WaterRight` model.** Every state has these fields in some form:
   - number;
   - owner;
   - priority date;
   - source (surface or ground);
   - flow (cfs) and volume (acre-feet);
   - uses;
   - status (decreed, licensed, permit, application, claim);
   - POD location;
   - link to the official record.

   Add `rawAttributes` for state-specific fields and show them in an expandable "All details" section.
4. **One "official record" deep link per state**, so users can always check against the source.
5. **A parcel tile pipeline as a script** (`tool/parcels/build_state.sh <ST>`): download, `ogr2ogr`, `tippecanoe -l parcels -Z12 -z16 --drop-densest-as-needed`, then upload to R2 as `<st>_parcels.pmtiles`. The Worker route generalizes from `/tiles/co/` to `/tiles/{st}/`. This repeats what already works for Colorado.

---

## Phase 2: More states

### Water rights sources (all free, public)

| State | Agency | Points of diversion / rights service | Notes |
|---|---|---|---|
| **Idaho** | IDWR | `gis.idwr.idaho.gov/hosting/rest/services/Allocation/WaterRightPods/FeatureServer` | Separate services for permits, applications and adjudication claims (`AppropriationPermitPods`, `AppropriationApplicationPods`, `AdjudicationClaimPods`). Excellent fit. |
| **Montana** | DNRC | `gis.dnrc.mt.gov/arcgis/rest/services/WRD/WMB_WaterRightsData/FeatureServer` (PODs + **places of use polygons**) and `WRD/WRQS` | Places of use make "which rights cover this parcel" possible, not just "nearby". The WRQS (wrqs.dnrc.mt.gov) has abstracts to link to. |
| **Nevada** | NDWR | `arcgis.water.nv.gov/arcgis/rest/services/NDWR/Water_Rights_Points_of_Diversion/FeatureServer` | `Water_Rights_POD_Active_Geocortex` is refreshed every business day. Huge demand: water is make-or-break for NV land deals. |
| **New Mexico** | OSE | `services2.arcgis.com/qXZbWTdPDbTjl7Dy/ArcGIS/rest/services/OSE_PODs/FeatureServer` (also `gis.ose.nm.gov/server_s/.../PODS/watersPods_currentFGDB`) | Includes wells and surface declarations. |
| **Arizona** | ADWR | Wells 55 Registry (`Well_Registry_2024` FeatureServer; interactive at azwatermaps.azwater.gov/WellReg) | Arizona's question is mostly **wells and AMA rules** (Active Management Areas, Assured Water Supply), not surface rights. Show the AMA/INA boundary plus nearby registered wells. |
| **Oregon** | OWRD | `gis.wrd.state.or.us/server/rest/services/...` + Oregon GeoHub downloads (PODs and **places of use**) | Places of use again, so parcel coverage is possible. |
| **Washington** | Ecology | `gis.ecology.wa.gov/serverext/rest/services/Authoritative/WR/MapServer` (surface diversions) and the Water Resources Explorer services | 2000 records per query. Wells come from the separate well-log data. |
| **Wyoming** | SEO | e-Permit (seoweb.wyo.gov/e-Permit) has a spatial search; no clean public feature service found | Needs a nightly bulk export into our own tiles, or scraping e-Permit. Do it after the easy states. |
| **Texas** | TWDB | `services.twdb.texas.gov/arcgis/rest/services/Public/WellReports/FeatureServer` (about 680k driller reports) | Texas groundwater follows the rule of capture, so the useful product is **"wells near this parcel + groundwater conservation district"**, not rights. A big market. |
| California | SWRCB | eWRIMS points of diversion (`gispublic.waterboards.ca.gov/.../Water_Rights/Points_of_Diversion`) | Messier data. Later. |

### Parcel sources

| State | Free statewide parcels? | Plan |
|---|---|---|
| Montana | **Yes**: Montana Cadastral (MSDI), monthly statewide download plus `gisservice.mt.gov/.../msdi_cadastral_map_v1/MapServer` | PMTiles, like Colorado |
| Idaho | Per county (free downloads at idaho.gov/parcels, INSIDE Idaho) | Merge the counties into one PMTiles. Start with the ag counties: Twin Falls, Jerome, Gooding, Canyon, Bonneville. |
| Nevada | Per county; Washoe and Clark are easy | Counties first |
| New Mexico | Statewide composite exists via NM RGIS / county data | PMTiles |
| Oregon / Washington | Statewide composites exist (ORMAP; WA Current Parcels) | PMTiles |
| Arizona / Texas / Wyoming | County by county, or paid | Fall back to a paid source |

**Paid fallback:** Regrid quotes about **$25k a year** for the nationwide Basic API plus tiles, too much for now. An alternative is **ReportAll USA** (per-county or per-state bulk purchases, cheap). Or launch a state without parcel outlines: tap a point and show water rights within X miles. That's still useful and costs nothing.

### Recommended order

1. **Idaho**: best water data, close to Utah, and many Utah agents also work in SE Idaho.
2. **Montana**: free statewide parcels **and** places-of-use polygons, so it gets the best answer quality of any state.
3. **Nevada**: the most acute water questions and a large rural-land market.
4. **New Mexico**, then **Arizona** (wells and AMA framing).
5. **Oregon / Washington.**
6. **Texas** (wells product) and **Wyoming** (needs ingestion work).

Each state takes roughly **2–4 days** once Phase 1 is done: wire the source, normalize the fields, write a tile build if free parcels exist, and QA about 20 known parcels.

**Marketing tie-in:** one landing page per state on auaha.app ("Idaho water rights lookup by address"). This copies the Threshold state-page generator in `auaha_web/scripts/states.json`.

---

## Phase 3: OnX-style map layers

Make the layers toggleable from a "Layers" sheet next to the basemap picker. All
sources below are free and national unless noted.

| Layer | Source | How |
|---|---|---|
| **Public land (BLM / USFS / NPS / State Trust)** | USGS **PAD-US** (Protected Areas Database), or BLM Surface Management Agency (SMA) services per state | Build PAD-US into one national PMTiles (about 1 GB) on R2. Color it like OnX: yellow BLM, green USFS, blue state. |
| **Topo** | Mapbox Outdoors (have it) + USGS 3DEP hillshade/contours (`basemap.nationalmap.gov`) | Raster tile overlay |
| **Satellite** | Mapbox Satellite (have it); USDA **NAIP** 60 cm imagery for recent farm detail | NAIP from the USGS/USDA image services |
| **Streams, canals, ditches** | USGS **NHD / NHDPlus HR** flowlines (canals and ditches are tagged) | National PMTiles or the USGS NHD MapServer. Very relevant: "is that ditch on my parcel?" |
| **Wells** | State well logs (UT DWRi, CO DWR permits, ID, NV, TX above) + USGS NWIS groundwater sites | Point layer, tap for depth, yield and date |
| **Flood zones** | FEMA **NFHL** (`hazards.fema.gov/.../NFHL/MapServer`) | Raster overlay. Agents ask for this constantly. |
| **Soils / farmland class** | USDA **SSURGO** (Soil Data Access) | Tap for soil type plus "prime farmland" or irrigated capability class |
| **Irrigated fields / crops** | USDA **Cropland Data Layer**; Utah's water-related land use layer | Overlay showing whether land was actually irrigated, which matters for forfeiture risk |
| **Water districts / irrigation companies / GW management areas** | State services (UT water districts, CO water divisions, AZ AMAs, TX GCDs) | Polygon tap: "you're in X irrigation company; shares are how water comes here" |
| **PLSS grid** | BLM CadNSDI (already queried) | Draw it as a toggleable grid |

Basemap work: add a **hybrid "Topo + Satellite"** style and remember the last style used.

---

## Phase 4: Features that make it a daily tool

- **Saved lookups (finish the stub):** save to Firestore with a note and a tag ("Smith ranch listing"). This turns Prior into a working file for each listing.
- **PDF water report:** one tap to a branded PDF with:
  - the parcel map;
  - the rights table;
  - priority dates in plain language;
  - links to official records;
  - the disclaimer.

  Agents attach it to listings or send it to buyers. Probably the most valuable paid feature, and it supports a higher tier.
- **Plain-English explainer per right:** priority date versus the river's call history, "decreed versus permit", "what is an acre-foot". Could use a cheap Claude call, with a strict "not legal advice" banner.
- **Change and transfer alerts:** watch a right number and get notified when a change application or transfer is filed. Utah's `wrprint` change-application fetch already exists.
- **Measure tool:** area and distance on the map (acres), like OnX.
- **Offline maps** for rural showings with no signal: Mapbox offline regions plus cached lookups.
- **Share link:** `auaha.app/prior/r/<id>` web view of a lookup, which also drives installs.
- **Water market context:** Utah Water Hub listings exist. Add the price-per-acre-foot history per area where markets publish it (WestWater, NV, CO-Big Thompson units).

## Phase 5: Business

- **Pricing:**
  - Free: 5 lookups a month.
  - Pro: unlimited.
  - New **Team / Brokerage** tier: shared saved lookups, branded PDFs, seats.
  - Consider a **per-state** price only if per-state costs (paid parcels) force it.
- **Channels:** state REALTOR associations' rural/land councils, the REALTORS Land Institute (RLI), farm and ranch brokerages, title companies, water attorneys, and appraisers (ASFMRA).
- **Positioning:** "OnX shows you the land. Prior shows you the water."

## Suggested next 30 days

1. Phase 1 refactor plus finishing Saved Lookups (about 1.5 weeks).
2. Idaho launch (water rights live; parcels for the 5 ag counties).
3. Public-land and streams/canals layers (the 2 most OnX-like, both free).
4. Update the paywall copy: "Utah, Colorado & Idaho".

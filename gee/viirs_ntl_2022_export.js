// Google Earth Engine script: export VIIRS annual nighttime lights 2022 for Buenos Aires province.
// Product: VIIRS Nighttime Day/Night Annual Band Composites V2.2 (Earth Observation Group, Colorado School of Mines)
// Band: average_masked = average radiance (nW/cm2/sr) with background noise, fires and outliers masked.
// Output: data/raw/viirs_ntl_2022_pba.tif (download from Google Drive after the export task finishes).
var region = ee.Geometry.Rectangle([-63.5, -41.2, -56.5, -33.2]);
var ntl = ee.ImageCollection('NOAA/VIIRS/DNB/ANNUAL_V22')
  .filterDate('2022-01-01', '2023-01-01').first()
  .select('average_masked');
Export.image.toDrive({
  image: ntl.clip(region), description: 'viirs_ntl_2022_pba',
  region: region, scale: 463.83, crs: 'EPSG:4326',
  maxPixels: 1e10, fileFormat: 'GeoTIFF'
});

# 04. PREPARE ENVIRONMENTAL  COVARIATES ############################################################
# SUMMARY
# Environmental covariates are predictor variables extracted from maps of soil properties and other
# spatial information. Like the soil variables, the environmental covariates will be used to train
# a random forest regression model to estimate the bulk density of soil samples that are missing
# data on such variable.
# Sampling environmental covariates requires the events to have spatial coordinates. Thus, we start
# by filtering out those event that are not geolocalized. Then we sample two data sets. The first is
# SoilGrids 250m v2.0, a collection of soil property maps available for six depth intervals, three
# of which are of our interest: 0-5, 5-15, and 15-30 cm. The soil properties of interest are clay,
# sand, bulk density, and SOC. The second data set is MapBiomas Land Use/Land Cover Collection 7.0.
# This data set contains data covering the period between 1985 and 2021. After sampling the raster
# layers, we identify and retain for each event the land use/land cover at the year at which it was
# collected in the field.
# Both SoilGrids and MapBiomas data are available on Google Earth Engine. Because sampling data on
# Google Earth Engine has limitations, we perform the operation using subsets containing at most
# 5000 or 1000 events for SoilGrids and MapBiomas, respectively.
# 
# Missing data is handled using the MIA approach described earlier for soil covariates.

# KEY RESULTS
# Out of the 15 141 existing events, 12 110 are geolocalized. With these events, we sampled data
# from SoilGrids 250m v2.0 (clay, sand, SOC, and bulk density) at three depth intervals (0-5, 5-15,
# and 15-30 cm).

# * GEE/projects/mapbiomas-workspace/public/collection7/mapbiomas_collection70_integration_v2
#   (MapBiomas Land Use/Land Cover Collection 7.0)
rm(list = ls())

# Install and load required packages
if (!require("data.table")) {
  install.packages("data.table")
}
if (!require("sf")) {
  install.packages("sf")
}
if (!require("rgee")) {
  install.packages("rgee", dependencies = TRUE)
  rgee::ee_install()
  # snap install google-cloud-cli --classic
}
if (!require("geobr")) {
  install.packages("geobr")
}

# Missingness in attribute
mia <-
  function(x) {
    is_na <- is.na(x)
    Xplus <- as.numeric(x)
    Xplus[is_na] <- as.numeric(+Inf)
    Xminus <- as.numeric(x)
    Xminus[is_na] <- as.numeric(-Inf)
    Xna <- rep("ISNOTNA", length(x))
    Xna[is_na] <- as.character("ISNA")
    out <- data.frame(Xplus = Xplus, Xminus = Xminus, Xna = Xna)
    return(out)
}

# Initialize Google Earth Engine
rgee::ee_Initialize()

# Read data processed in the previous script
febr_data <- data.table::fread("mapbiomas-solos/data/03-febr-data.txt", dec = ",", sep = "\t")
nrow(unique(febr_data[, "id"])) # 15 141
nrow(febr_data) # 52 696
colnames(febr_data)

# Create spatial object
# First filter out those samples without coordinates
# Also keep a single sample per soil profile
is_na_coordinates <- is.na(febr_data[, coord_x]) | is.na(febr_data[, coord_y])
sp_febr_data <- febr_data[!is_na_coordinates, ]
nrow(unique(sp_febr_data[, c("dataset_id", "observacao_id")]))
# 12 110
first <- function(x) x[1, ]
sf_febr_data <- 
  sp_febr_data[, first(id),
  by = c("dataset_id", "observacao_id", "coord_x", "coord_y", "data_coleta_ano")]
sf_febr_data[, V1 := NULL]
nrow(sf_febr_data)
# 12 121
sf_febr_data <- sf::st_as_sf(sf_febr_data, coords = c("coord_x", "coord_y"), crs = 4326)
brazil <- geobr::read_country()
x11()
plot(brazil, reset = FALSE)
plot(sf_febr_data, add = TRUE, col = "black", cex = 0.5)

# Prepare for sampling on GEE
n_max <- 5000
n_points <- nrow(sf_febr_data)
n_lags <- ceiling(n_points / n_max)
lag_width <- ceiling(n_points / n_lags)
lags <- rep(1:n_lags, each = lag_width)
lags <- lags[1:n_points]

# Soil Grids 250m v2.0: bdod_mean
bdod_mean <- list()
for (i in 1:n_lags) {
  bdod_mean[[i]] <- rgee::ee_extract(
    x = rgee::ee$Image("projects/soilgrids-isric/bdod_mean"),
    y = sf_febr_data[lags == i, ],
    scale = 250
  )
}
bdod_mean <- data.table::rbindlist(bdod_mean)
bdod_mean[, c("bdod_30.60cm_mean", "bdod_60.100cm_mean", "bdod_100.200cm_mean") := NULL]
# bdod_mean[, c("dataset_id", "observacao_id", "data_coleta_ano") := NULL]
nrow(bdod_mean)

# Soil Grids 250m v2.0: clay_mean
clay_mean <- list()
for (i in 1:n_lags) {
  clay_mean[[i]] <- rgee::ee_extract(
    x = rgee::ee$Image("projects/soilgrids-isric/clay_mean"),
    y = sf_febr_data[lags == i, ],
    scale = 250
  )
}
clay_mean <- data.table::rbindlist(clay_mean)
clay_mean[, c("clay_30.60cm_mean", "clay_60.100cm_mean", "clay_100.200cm_mean") := NULL]
# clay_mean[, c("dataset_id", "observacao_id", "data_coleta_ano") := NULL]
nrow(clay_mean)

# Soil Grids 250m v2.0: sand_mean
sand_mean <- list()
for (i in 1:n_lags) {
  sand_mean[[i]] <- rgee::ee_extract(
    x = ee$Image("projects/soilgrids-isric/sand_mean"),
    y = sf_febr_data[lags == i, ],
    scale = 250
  )
}
sand_mean <- data.table::rbindlist(sand_mean)
sand_mean[, c("sand_30.60cm_mean", "sand_60.100cm_mean", "sand_100.200cm_mean") := NULL]
# sand_mean[, c("dataset_id", "observacao_id", "data_coleta_ano") := NULL]
nrow(sand_mean)

# Soil Grids 250m v2.0: soc_mean
soc_mean <- list()
for (i in 1:n_lags) {
  soc_mean[[i]] <- rgee::ee_extract(
    x = rgee::ee$Image("projects/soilgrids-isric/soc_mean"),
    y = sf_febr_data[lags == i, ], scale = 250
  )
}
soc_mean <- data.table::rbindlist(soc_mean)
soc_mean[, c("soc_30.60cm_mean", "soc_60.100cm_mean", "soc_100.200cm_mean") := NULL]
# soc_mean[, c("dataset_id", "observacao_id", "data_coleta_ano") := NULL]
nrow(soc_mean)





# Collate data from SoilGrids
# use cbind()
merge_by <- c("dataset_id", "observacao_id", "data_coleta_ano", "lag")
SoilGrids <- merge(bdod_mean, clay_mean)
nrow(SoilGrids)

idx <- which(duplicated(SoilGrids[, ..merge_by]))
SoilGrids[idx, ]

nrow(SoilGrids)
all(bdod_mean[["observacao_id"]] == soc_mean[["observacao_id"]])

SoilGrids <- merge(SoilGrids, sand_mean, by = merge_by)
SoilGrids <- merge(SoilGrids, soc_mean, by = merge_by)
colnames(SoilGrids) <- gsub("_mean", "", colnames(SoilGrids), fixed = TRUE)
nrow(SoilGrids)

# Prepare to sample MapBiomas on GEE
n_max <- 1000
n_points <- nrow(sf_febr_data)
n_lags <- ceiling(n_points / n_max)
lag_width <- ceiling(n_points / n_lags)
lags <- rep(1:n_lags, each = lag_width)
lags <- lags[1:n_points]

# Sample MapBiomas LULC
gee_path <- "projects/mapbiomas-workspace/public/collection7/mapbiomas_collection70_integration_v2"
mapbiomas <- list()
for (i in 1:n_lags) {
  mapbiomas[[i]] <- rgee::ee_extract(
    x = ee$Image(gee_path),
    y = sf_febr_data[lags == i, ],
    scale = 30,
    fun = rgee::ee$Reducer$first()
  )
}
mapbiomas <- data.table::rbindlist(mapbiomas)

# Get LULC class at the year of sampling
colnames(mapbiomas) <- gsub("classification_", "", colnames(mapbiomas))
lulc_idx <- match(mapbiomas[, data_coleta_ano], colnames(mapbiomas))
lulc <- as.matrix(mapbiomas)
lulc <- lulc[cbind(1:nrow(lulc), lulc_idx)]
mapbiomas[, LULC := as.factor(lulc)]
nrow(mapbiomas)
# 12 121

# Create bivariate covariates indicating natural land covers and agricultural land uses
natural <- c(1, 3, 4, 5, 10, 49, 11, 12, 32, 29, 50, 13)
agriculture <- c(14, 15, 18, 19, 39, 20, 40, 62, 41, 36, 46, 47, 48, 9, 21)
mapbiomas[, natural := 0]
mapbiomas[LULC %in% natural, natural := 1]
mapbiomas[, agriculture := 0]
mapbiomas[LULC %in% agriculture, agriculture := 1]
mapbiomas[, as.character(1985:2021) := NULL]
nrow(mapbiomas)

sf_febr_data <- merge(sf_febr_data, SoilGrids, by = merge_by)
sf_febr_data <- merge(sf_febr_data, mapbiomas, by = merge_by)
nrow(sf_febr_data)

# Merge data
sp_febr_data <- merge(sp_febr_data, sf_febr_data, by = c("dataset_id", "id"))
sp_febr_data[, geometry := NULL]
febr_data <- data.table::rbindlist(list(sp_febr_data, febr_data[is_na_coordinates, ]),
  use.names = TRUE, fill = TRUE)

# Impute missing
which_cols <- which(grepl("([0-9])\\.([0-9])", colnames(febr_data), perl = TRUE))
for (i in which_cols) {
  y <- mia(febr_data[[i]])
  colnames(y) <- gsub("X", toupper(colnames(febr_data)[i]), colnames(y))
  febr_data <- cbind(febr_data, y)
}
febr_data[, colnames(febr_data)[which_cols] := NULL]

# Write data to disk
data.table::fwrite(febr_data, "mapbiomas-solos/data/04-febr-data.txt", sep = "\t", dec = ",")

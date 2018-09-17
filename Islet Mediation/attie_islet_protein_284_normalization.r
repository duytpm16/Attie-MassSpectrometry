load("~/Desktop/Attie/Attie_rZ_QTL_Viewer_V3.RData")

intersect.samples <- intersect(rownames(dataset.islet.rnaseq$expr), rownames(dataset.islet.proteins$expr))
saveRDS(intersect.samples,'Attie_islet_intersect_samples.rds')


prefix <- "attie_islet_protein_284"
raw <- read.table("~/Desktop/Attie/Islet Proteins/DO_islet_proteomics_non_normalized.txt", sep = '\t', header = TRUE)
samples <- read.table("~/Desktop/Attie/attie_DO_sample_annot.txt", header = TRUE ,sep = "\t")
chr_m_y <- read.csv("~/Desktop/Attie/attie_sample_info_ChrM_Y.csv") 



### Variable names to store the data
raw_file <- paste0(prefix,"_filtered_raw.rds")
norm_file <- paste0(prefix,"_normalized.rds")
norm_rz_file <- paste0(prefix,"_rZ_normalized.rds")
samples_file <-  paste0(prefix, "_samples_annot.rds")




### Fixing the name of two columns in the samples dataframe to match a data dictionary that will be used later in other scripts
colnames(samples)[grep('wave', colnames(samples))] <- 'DOwave'
colnames(raw)[grep('Batch', colnames(raw))] <- 'batch'

samples$Mouse.ID <- gsub('-', '', samples$Mouse.ID)
raw$Mouse.ID <- gsub('-', '', raw$Mouse.ID)
chr_m_y$Mouse.ID <- gsub('-', '', chr_m_y$Mouse.ID)

colnames(samples) <- gsub('_','.',colnames(samples))




### Preparing samples dataframe
#   First, merge columns that do not contain protein abundance to samples data.frame.
#   Next merge unique columns in chr_m_y dataframe to samples dataframe.
#       samples: 375 x 10 (Reduced to 375 because control ('Std) mice were removed)
samples <- merge(samples, raw[,c("Mouse.ID","Injection_order","Plate_number","batch")], by = "Mouse.ID")
samples <- merge(samples, chr_m_y[,c('Mouse.ID','generation','chrM','chrY')], by = "Mouse.ID")
colnames(samples) <- gsub('_','.',colnames(samples))




### Removing columsn that are not proteins
#   Keep protein columns that have less than 50% NAs across samples.
#   Remove '-' in Mouse.ID column
#       islet_protein_raw: 439 x 5434
raw <- raw[,!(colnames(raw) %in% c("Injection_order","Plate_number","batch"))]

raw <-  raw[,colSums(is.na(raw)) < .50 * nrow(raw)]



### Remove control samples.
#       Number of controls: 64 with some duplicates
#       Number of DOs: 375 with some duplicates (DO-174, DO-374)
ctrl <- raw[grep("Std", raw$Mouse.ID),]
raw <- raw[grep('DO', raw$Mouse.ID),]

raw <- raw[raw$Mouse.ID %in% intersect.samples,]


data.log = log(raw[,!(colnames(raw) %in% 'Mouse.ID')])
samples = samples[samples$Mouse.ID %in% intersect.samples,]

### Set up batch and model for comBat
samples$sex  = factor(samples$sex)
samples$DOwave = factor(samples$DOwave)
mod = model.matrix(~sex, data = samples)
batch = as.factor(samples$batch)


### Impute missing data and combat normalization
chg = 1e6
iter = 1
repeat({
  
  print(paste("Iteration", iter))
  
  # Impute missing data using pca
  miss = which(is.na(data.log))
  print(paste(length(miss), "missing points."))
  
  pc.data = pca(data.log, method = "bpca", nPcs = 5)
  data.compl = completeObs(pc.data)
  
  # Batch adjust.
  # ComBat wants the data with variable in rows and samples in columns.
  data.cb = ComBat(dat = t(data.compl), batch = batch, mod = mod)
  data.cb = t(data.cb)
  
  # Calculate the change.
  chg = sum((data.compl[miss] - data.cb[miss])^2)
  print(paste("SS Change:", chg))
  
  # Put the missing data back in and impute again.
  if(chg > 5 & iter < 20) {
    
    data.cb[miss] = NA
    data.log = data.cb
    iter = iter + 1    
    
  }else{
    
    data.log = data.cb
    break
    
  }
})


### Find the duplicated samples and keep the one with fewer NAs in original data
dupl = which(duplicated(raw$Mouse.ID))
prop.missing = rowMeans(is.na(raw))
unique.samples = unique(raw$Mouse.ID)
keep = rep(FALSE, nrow(raw))

for(i in 1:length(unique.samples)){
  
  sample = unique.samples[i]
  wh = which(raw$Mouse.ID == sample)
  wh = wh[which.min(prop.missing[wh])]
  keep[wh] = TRUE
  
} 

data.log <- data.log[keep,]
raw <- raw[keep,]
rownames(data.log) <- raw$Mouse.ID
rownames(raw) <- raw$Mouse.ID
raw <- raw[,!(colnames(raw) %in% "Mouse.ID")]



### Removing duplicates in the samples dataframe and changing Mouse.ID column name to lowercase for QTL Viewer
samples = samples[match(rownames(data.log), samples$Mouse.ID),]
rownames(samples) <- samples$Mouse.ID
colnames(samples)[grep('mouse.id', colnames(samples), ignore.case = TRUE)] <- 'mouse.id'



### Rank Z of normalized data.
rankZ = function(x) {
  x = rank(x, na.last = "keep", ties.method = "average") / (sum(!is.na(x)) + 1)
  return(qnorm(x))
} # rankZ()

data.rz = data.log

for(i in 1:ncol(data.rz)) {
  data.rz[,i] = rankZ(data.rz[,i])
}



### Saving the data to current working directory
saveRDS(raw, raw_file)
saveRDS(data.log, norm_file)
saveRDS(data.rz, norm_rz_file)
saveRDS(samples, samples_file)
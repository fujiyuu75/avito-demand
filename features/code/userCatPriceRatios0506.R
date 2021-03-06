#install.packages("fasttime")
rm(list=ls())
gc();gc();gc()
library(data.table)
library(RcppRoll)
library(fasttime)
library(Hmisc)
library(RcppRoll)

path = '~/avito/data/'
path = '/Users/dhanley2/Documents/avito/data/'

# Write out the <ip, device, os> level
keepcols = c("image_top_1", "activation_date", "deal_probability")
trndf = data.table(read_csv(paste0(path, 'train.csv')))
trndf = trndf[,keepcols,with=F]
trndf[,is_train:=1]
gc(); gc()
tstdf = data.table(read_csv(paste0(path, 'test.csv')))
tstdf = tstdf[,keepcols[1:(length(keepcols)-1)],with=F]
tstdf[, is_train:=0]
tstdf[, deal_probability := NA]
gc(); gc()
alldf = rbind(trndf, tstdf)
train_length = nrow(trndf)
alldf[, index := 1:nrow(alldf)]
rm(trndf, tstdf)
gc(); gc()

##### These are our five folds
foldls = list(c("2017-03-15", "2017-03-16", "2017-03-17"), 
              c("2017-03-18", "2017-03-19", "2017-03-20"), 
              c("2017-03-21", "2017-03-22", "2017-03-23"), 
              c("2017-03-24", "2017-03-25", "2017-03-26"), 
              c("2017-03-27", "2017-03-28", "2017-03-29", 
                "2017-03-30", "2017-03-31", "2017-04-01",
                "2017-04-02", "2017-04-03","2017-04-07"))
for (f in foldls) print(nrow(alldf[(is_train == 1)][(activation_date %in% as.Date(f))]))
for (col in keepcols) print(paste(col, length(unique(alldf[[col]]))))

table(alldf[is_train==1]$activation_date)
alldf[, fold_:=6]
alldf[activation_date %in% as.Date(foldls[[1]]), fold_:= 1]
alldf[activation_date %in% as.Date(foldls[[2]]), fold_:= 2]
alldf[activation_date %in% as.Date(foldls[[3]]), fold_:= 3]
alldf[activation_date %in% as.Date(foldls[[4]]), fold_:= 4]
alldf[activation_date %in% as.Date(foldls[[5]]), fold_:= 5]
table(alldf$activation_date, alldf$fold_)

#df = copy(alldf)
#fold = 6
#cols_ = "image_top_1"
#prior = 200
# Function for out of fold Bayes mean
oofBMean = function(df, fold, cols_, prior = 200, allrows_ = FALSE){
  glob_mean = mean(df[(fold_ != fold) & (is_train == 1)]$deal_probability)
  glob_ct   = nrow(df[(fold_ != fold) & (is_train == 1)])
  # Aggregate the infold data
  indf = df[(fold_ != fold) & (is_train == 1),.(.N, mean(deal_probability)), by = c(cols_)]
  if (allrows_){
    outdf = df[(is_train == 0), c(cols_), with=F]
  }else{
    outdf = df[(fold_ == fold) & (is_train == 1), c(cols_, "fold_"), with=F]
  }
  setnames(indf, c(cols_, "count", "mean"))
  indf[, bmean := ((mean*count)+(glob_mean*prior))/(count+prior)]
  indf[,mean := NULL]
  indf[,count := NULL]
  outdf[, idx := 1:nrow(outdf)]
  outdf = merge(outdf, indf, by = cols_, all.x = T)[order(idx)]
  outdf[ is.na(bmean), bmean:= glob_mean]
  return(outdf$bmean)
}


folds_ = sort(unique(alldf[(is_train == 1)]$fold_))
for (col in keepcols) print(paste(col, length(unique(alldf[[col]]))))

keepcols
# Get bayes mean user_id using folds
encodeDF = function(alldf, col, prior = 1000){
  alldf[, tmpcol := -1]
  for (fold in folds_) alldf[(fold_ == fold) & (is_train == 1), tmpcol := oofBMean(alldf, fold, col, prior )]
  alldf[(is_train == 0), tmpcol :=  oofBMean(alldf, 6, col, allrows_ = TRUE, prior)]
  setnames(alldf, "tmpcol", paste0(col, "_enc"))
  return(alldf)
}

alldf = encodeDF(alldf, "image_top_1", prior = 150)

# Rolling mean of image_top_1
alldf = alldf[order(image_top_1)]
alldf$image_top_1_oof_rmean = roll_mean(alldf$image_top_1_enc,200, na.rm=TRUE, fill=NA, align='right')
alldf$image_top_1_oof_rmean[is.na(alldf$image_top_1_oof_rmean)] = -.1
plot(alldf$image_top_1_oof_rmean[1:1000000])


alldf = alldf[order(index)]
alldf_enc = alldf[, "image_top_1_oof_rmean", with = F]

# Write out the files
writeme = function(df, name){
  write.csv(df, 
            gzfile(paste0(path, '../features/', name,'.gz')), 
            row.names = F, quote = F)
}
writeme(alldf_enc, 'img_top_oof_bayes_mean')
rm(list=ls())
gc();gc();gc()


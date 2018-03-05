#############################
##
## Chapter 9
##
############################

library(RODBC)

## with actual FA funcitons
library(psych)
library(Hmisc)
## for data munching and visualization
library(ggplot2)
library(plyr)
library(pastecs)
library(RODBC)

dbConn <- odbcDriverConnect('driver={SQL Server};server=TOMAZK\\MSSQLSERVER2017;database=ServerInfo;trusted_connection=true')
server.feature <- sqlQuery(dbConn, 'SELECT * FROM Server_info')
close(dbConn)


# feature 
server.feature <- dataset
fa.model <- fa(server.feature,7,n.obs = 459,fm="pa",scores="regression", use="pairwise",rotate="varimax") #can use WLS - weighted least squares
fa.model.r <- target.rot(fa.model)
fa.diagram(fa.model.r)










#data checking
View(server.feature)


####  check for the FA criteria
## Outliers
boxplot(server.feature)



# 12, 18, 24, 27

# replace value 25 with N/A
server.feature$XE12[server.feature$XE12=="25"]<-NA
server.feature$XE18[server.feature$XE18=="25"]<-NA
server.feature$XE24[server.feature$XE24=="25"]<-NA
server.feature$XE27[server.feature$XE27=="25"]<-NA


#get descriptive statistics
summary(server.feature)



#check the correlations!
cor(server.feature, use="complete.obs", method="kendall") 


#Heatmap will show us correlations
#png('server_features.png')
cor.plot(server.feature,numbers=TRUE,main="Server Features")
dev.off()


########################
### Factor analysis
########################

#Assume we don't know how many factors we can extract, so we will do exploratory FA
fa.parallel(server.feature, fa="fa")
vss(server.feature)


#now that we know the number of factors, let's continue with analysis
fa.model <- fa(server.feature
               ,7
               #,n.obs = 459
               ,fm="pa"
               ,scores="regression"
               #,use="pairwise"
               ,rotate="varimax") #can use WLS - weighted least squares


#plot the factors correlation - hard to see anything
fa.diagram(fa.model)


#orig target.rot function
# function (x, keys = NULL)                   
# {                                           
#     if (!is.matrix(x) & !is.data.frame(x)) {
#         if (!is.null(x$loadings))           
#             x <- as.matrix(x$loadings)      
#     }    


# Inject the target.rot2 function because the original is not working all of a sudden?!
target.rot2 <- function (x, keys=NULL,m = 4) 
{
  if(!is.matrix(x) & !is.data.frame(x) )  {
    if(!is.null(x$loadings)) x <- as.matrix(x$loadings)
  } else {x <- x}   
  if (ncol(x) < 2) 
    return(x)
  dn <- dimnames(x)
  if(is.null(keys)) {xx <- varimax(x)
  x <- xx$loadings
  Q <- x * abs(x)^(m - 1)} else {Q <- keys}
  U <- lm.fit(x, Q)$coefficients
  d <- diag(solve(t(U) %*% U))
  U <- U %*% diag(sqrt(d))
  dimnames(U) <- NULL
  z <- x %*% U
  if (is.null(keys)) {U <- xx$rotmat %*% U } else {U <- U}
  ui <- solve(U)
  Phi <- ui %*% t(ui)
  dimnames(z) <- dn
  class(z) <- "loadings"
  result <- list(loadings = z, rotmat = U,Phi = Phi)
  class(result) <- c("psych","fa")
  return(result)
}


#fa.model <- as.matrix(fa.model)
fa.model.r <- target.rot2(fa.model)


df_loadings <- data.frame(fa.model$loadings[1])


fa.loadings <- as.list.data.frame(fa.model$loadings)




#Check the standardized loadings
fa.model.r


#plot the factors correlation - hard to see anything
fa.diagram(fa.model.r)

install.packages("pastecs")

library(pastecs)


# values are already suppressed
# for export into data.frame
FA.loadings.server.features <- fa.model.r$loadings


str(FA.loadings.server.features)
unlisted.FA.loadings <- unlist(FA.loadings.server.features)

head(unlisted.FA.loadings, n=20)

mat <- as.matrix(unlisted.FA.loadings, nrow=32,ncol=7,byrow = TRUE)

as.data.frame(mat, row.names = NULL, stringsAsFactors = default.stringsAsFactors(), col.names = names(x))


# save loadings
fa.regression_Score <- data.frame(fa.model$scores)

server.feature.fa <- cbind(server.feature, fa.regression_Score)

#these values are used for further analysis
head(data_person.fa)

#heatmap

str(server.feature.fa)

library(d3heatmap)

#heatmap on the whole dataset
server.feature.matrix <- data.matrix(server.feature)							
heatmap(server.feature.matrix, Rowv=NA, Colv=NA, col = heat.colors(256), scale="column", margins=c(5,10))


#heatmap with factors
server.feature.fa.matrix <- data.frame(server.feature.fa[c("PA1","PA2","PA3","PA4","PA5","PA6","PA7")])							

#Do the ordering
#server.feature.fa.matrix <- server.feature.fa.matrix[order("PA1"),]
server.feature.fa.matrix <- data.matrix(server.feature.fa.matrix)
heatmap(server.feature.fa.matrix, Rowv=NA, Colv=NA, col = heat.colors(256), scale="column", margins=c(5,10))



#clustering on PAF Regression scores
library(cluster)

fa.reg.score <- data.frame(fa.model$scores)

#show Clustering in POwerBI!!!!



##############
## Work Loads
##############


library(car)
library(ggplot2)

setwd("C:\\Users\\TomazK\\Documents\\06-SQL\\CHapter09")

dataset <- read.csv("workloads.csv", header=TRUE, sep=";")

str(dataset)

colnames(dataset)[1] <- "WL_ID"
dataset$Parameter1 <- as.numeric(dataset$Parameter1)
dataset$Parameter2 <- as.numeric(dataset$Parameter2)

#recode WLD
dataset$WL_ID <- as.numeric(recode(dataset$WL_ID, "'WL1'=1; 'WL2'=2;'WL3'=3"))

dataset <- data.frame(dataset)
dataset <- dataset[2:4]

#calculate Mahalonobis distance to check for the outlier
m.dist <- mahalanobis(dataset, colMeans(dataset), cov(dataset))
dataset$maha_dist <- round(m.dist)

# Mahalanobis Outliers - Threshold set to 7
dataset$outlier_mah <- "No"
dataset$outlier_mah[dataset$maha_dist > 7] <- "Yes"


# Scatterplot for checking outliers using Mahalanobis 
ggplot(dataset, aes(x = Parameter1, y = Parameter2, color = outlier_mah)) +
  geom_point(size = 5, alpha = 0.6) +
  labs(title = "Mahalanobis distances for multivariate regression outliers",
       subtitle = "Comparison on 1 parameter for three synthetic Workloads") +
  xlab("Parameter 1") +
  ylab("Parameter 2") +
  scale_x_continuous(breaks = seq(5, 55, 5)) +
  scale_y_continuous(breaks = seq(0, 70, 5))    + geom_abline(aes(intercept = 12.5607 , slope = 0.5727))

# We can also add a regression line
# lm(Parameter1~Parameter2, data=datasaet)



LM.man <- Anova(lm(cbind(Parameter1, Parameter2) ~ WL_ID, data=dataset))
summary(LM.man)


MAN.WL <- manova(cbind(Parameter1, Parameter2) ~ WL_ID, data=dataset)
summary(MAN.WL)

library(gridExtra)
results <- summary.aov(MAN.WL)
results


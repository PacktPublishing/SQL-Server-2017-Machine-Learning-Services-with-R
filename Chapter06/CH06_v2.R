#############################
##
## Chapter 6
##
############################

library(RODBC)
library(RevoScaleR)

dbConn <- odbcDriverConnect('driver={SQL Server};server=TOMAZK\\MSSQLSERVER2017;database=TutorialDB_DL;trusted_connection=true')
dr_rent <- sqlQuery(dbConn, 'SELECT * FROM Rental_data')
close(dbConn)


head(dr_rent, n=2)

cor(dr_rent$Holiday, dr_rent$RentalCount)

cor(dr_rent$FWeekDay, dr_rent$RentalCount)

cor(dr_rent$Month, dr_rent$RentalCount)

cor_HR <- cor(dr_rent$Holiday, dr_rent$RentalCount)
cor_FR <- cor(dr_rent$FWeekDay, dr_rent$RentalCount)
cor_MR <- cor(dr_rent$Month, dr_rent$RentalCount)
d <- data.frame(cbind(cor_HR, cor_FR, cor_MR))



library(corrplot)

R<-cor(dr_rent)
head(round(R,2))
corrplot(R, method="color")
corrplot(R, method="pie")

corrplot(R, method="number", type="upper")

corrplot(R, method="number", type="upper", sig.level = 0.01)


cor.mtest <- function(mat, ...) {
  mat <- as.matrix(mat)
  n <- ncol(mat)
  p.mat<- matrix(NA, n, n)
  diag(p.mat) <- 0
  for (i in 1:(n - 1)) {
    for (j in (i + 1):n) {
      tmp <- cor.test(mat[, i], mat[, j], ...)
      p.mat[i, j] <- p.mat[j, i] <- tmp$p.value
    }
  }
  colnames(p.mat) <- rownames(p.mat) <- colnames(mat)
  p.mat
}
# matrix of the p-value of the correlation
p.mat <- cor.mtest(dr_rent)


col <- colorRampPalette(c("#BB4444", "#EE9988", "#FFFFFF", "#77AADD", "#4477AA"))
corrplot(R, method="color", col=col(200),  
         type="upper", order="hclust", 
         addCoef.col = "black", # Add coefficient of correlation
         tl.col="black", tl.srt=45, #Text label color and rotation
         # Combine with significance
         p.mat = p.mat, sig.level = 0.01, insig = "blank", 
         # hide correlation coefficient on the principal diagonal
         diag=FALSE 
)

#year
dr_rent_sub <- dr_rent[c(1)]

#rent
dr_rent_sub <- dr_rent[c(4)]


#all rest
dr_rent_sub <- dr_rent[c(2,3,5:10)]
boxplot(dr_rent_sub)


library(randomForest)
fit_RF <- randomForest(factor(dr_rent$RentalCount)~., data=dr_rent)
VI_F <- importance(fit_RF)

VI_F<- data.frame(VI_F)
names <- row.names(VI_F)

VI_F <- data.frame(cbind(names, VI_F))


Formula_correlation =  ~ RentalCount + Year + Month + Day  + WeekDay + Snow + Holiday 
allCor <- rxCovCor(Formula_correlation, data = dr_rent, type = "Cor")
allCor

Formula_correlation =  ~ RentalCount + Year + Month + Day  + WeekDay + Snow + Holiday 
allCov <- rxCovCor(Formula_correlation, data = dr_rent, type = "Cov")
summary(allCov)
allCov
allCov$CovCor
################## REVOSCALE #########################

### supervised!


Formula_supervised = RentalCount ~ Year + Month + Day  + WeekDay + Snow + Holiday 

#rxLinMod
rent_lm <- rxLinMod(formula=Formula_supervised, data = dr_rent)
summary(rent_lm)
rent_Pred <- rxPredict(modelObject = rent_lm, data = dr_rent, extraVarsToWrite=c("RentalCount","Year","Month","Day"), writeModelVars = TRUE)


#rxGlm using poisson
rent_glm <- rxGlm(formula = Formula_supervised, family = poisson(), dropFirst = TRUE, data = dr_rent)
summary(rent_glm)
rent_Pred <- rxPredict(modelObject = rent_glm, data = dr_rent, extraVarsToWrite=c("RentalCount","Year","Month","Day"), writeModelVars = TRUE)

#rxGlm using gamma
rent_glm <- rxGlm(formula = Formula_supervised, family = Gamma, dropFirst = TRUE, data = dr_rent)
summary(rent_glm)
rent_Pred <- rxPredict(modelObject = rent_glm, data = dr_rent, extraVarsToWrite=c("RentalCount","Year","Month","Day"), writeModelVars = TRUE)

rent_glm <- rxGlm(formula=Formula_supervised, family = Gamma, dropFirst=TRUE,
                       data=dr_rent, variableSelection = rxStepControl(scope = ~ Year + Month + Snow + Holiday + Day + WeekDay))

summary(rent_glm)


#rxLogit
rent_logit <- rxLogit(formula=Formula_supervised, data = dr_rent)
#will not work, since the RentalCount is not binary.


#rxDTree
rent_DTree <- rxDTree(formula = Formula_supervised, data = dr_rent)
summary(rent_DTree)

rentCp <- rxDTreeBestCp(rent_DTree)
rent.dtree1 <- prune.rxDTree(rent_DTree, cp=rentCp)
rent.dtree2 <- rxDTree(formula=Formula_supervised, data = dr_rent, pruneCp="auto")

rent.dtree1[[3]] <- rent.dtree2[[3]] <- NULL
all.equal(rent.dtree1, rent.dtree2)


##########################################################################################################################################

##	Split the data set into a training and a testing set 

##########################################################################################################################################

# Randomly split the data into a training set and a testing set, with a splitting % p.
# p % goes to the training set, and the rest goes to the testing set. Default is 70%. 


library(caTools)
Split <- .70
sample <- sample.split(dr_rent$RentalCount, SplitRatio = Split)
train_dr_rent <- subset(dr_rent, sample == TRUE)
test_dr_rent  <- subset(dr_rent, sample == FALSE)



##########################################################################################################################################

##	Specify the variables to keep for the training 

##########################################################################################################################################

# Write the formula after removing variables not used in the modeling.


variables_all <- rxGetVarNames(dr_rent)
variables_to_remove <- c("FSnow", "FWeekDay", "FHoliday")
traning_variables <- variables_all[!(variables_all %in% c("RentalCount", variables_to_remove))]
formula <- as.formula(paste("RentalCount ~", paste(traning_variables, collapse = "+")))
#formula <- paste("RentalCount ~", paste(traning_variables, collapse = "+"))
data.frame(formula)


##########################################################################################################################################

##	Random Forest Training and saving the model to SQL

##########################################################################################################################################



# Train the Random Forest.
forest_model <- rxDForest(formula = formula,
                          data = train_dr_rent,
                          nTree = 40,
                          minSplit = 10,
                          minBucket = 5,
                          cp = 0.00005,
                          seed = 5)

# Save the Random Forest in SQL. The compute context is set to Local in order to export the model. 
trained_model <- as.raw(serialize(forest_model, connection=NULL))

#calculate accuracy
y_train <- train_dr_rent$RentalCount
y_test <- test_dr_rent$RentalCount

y_predicted<- rxPredict(forest_model,test_dr_rent)

predict_forest <-data.frame(actual=y_test,pred=y_predicted)
predict_forest$RentalCount_Pred <- as.integer(predict_forest$RentalCount_Pred)
#ConfMat <- confusionMatrix(table(predict_forest$actual,predict_forest$RentalCount_Pred))
#install.packages("MLmetrics")
library(MLmetrics)

accu <- LogLoss(y_pred = predict_forest$RentalCount_Pred , y_true =predict_forest$actual)
accuracy <- accu


##########################################################################################################################################

##	Gradient Boosted Trees Training and saving the model to SQL

##########################################################################################################################################

# Train the GBT.
btree_model <- rxBTrees(formula = formula,
                        data = train_dr_rent,
                        learningRate = 0.05,
                        minSplit = 10,
                        minBucket = 5,
                        cp = 0.0005,
                        nTree = 40,
                        seed = 5,
                        lossFunction = "gaussian")


trained_model_BT <- as.raw(serialize(btree_model, connection=NULL))

y_predicted<- rxPredict(btree_model,test_dr_rent)
predict_btree <-data.frame(actual=y_test,pred=y_predicted)
accu <- LogLoss(y_pred = predict_btree$RentalCount_Pred , y_true =predict_btree$actual)

################################
## Model evaluation
###############################


# Write a function that computes the AUC, Accuracy, Precision, Recall, and F-Score.
evaluate_model <- function(observed, predicted_probability, threshold, model_name) { 
  
  # Given the observed labels and the predicted probability, plot the ROC curve and determine the AUC.
  data <- data.frame(observed, predicted_probability)
  data$observed <- as.numeric(as.character(data$observed))
  if(model_name =="RF"){
    rxRocCurve(actualVarName = "observed", predVarNames = "predicted_probability", data = data, numBreaks = 1000, title = "RF" )
  }else{
    rxRocCurve(actualVarName = "observed", predVarNames = "predicted_probability", data = data, numBreaks = 1000, title = "GBT" )
  }
  ROC <- rxRoc(actualVarName = "observed", predVarNames = "predicted_probability", data = data, numBreaks = 1000)
  auc <- rxAuc(ROC)
  
  # Given the predicted probability and the threshold, determine the binary prediction.
  predicted <- ifelse(predicted_probability > threshold, 1, 0) 
  predicted <- factor(predicted, levels = c(0, 1)) 
  
  # Build the corresponding Confusion Matrix, then compute the Accuracy, Precision, Recall, and F-Score.
  confusion <- table(observed, predicted)
  print(model_name)
  print(confusion) 
  tp <- confusion[1, 1] 
  fn <- confusion[1, 2] 
  fp <- confusion[2, 1] 
  tn <- confusion[2, 2] 
  accuracy <- (tp + tn) / (tp + fn + fp + tn) 
  precision <- tp / (tp + fp) 
  recall <- tp / (tp + fn) 
  fscore <- 2 * (precision * recall) / (precision + recall) 
  
  # Return the computed metrics.
  metrics <- list("Accuracy" = accuracy, 
                  "Precision" = precision, 
                  "Recall" = recall, 
                  "F-Score" = fscore,
                  "AUC" = auc) 
  return(metrics) 
} 


##########################################################################################################################################

##	Random forest  Scoring 

##########################################################################################################################################



RF_Scoring <- rxPredict(forest_model, data = train_dr_rent, overwrite = T, type = "response",extraVarsToWrite = c("RentalCount"))

Prediction_RF <- rxImport(inData = RF_Scoring, stringsAsFactors = T, outFile = NULL)
observed <- Prediction_RF$RentalCount


# Compute the performance metrics of the model.
Metrics_RF <- evaluate_model(observed = observed, predicted_probability = Prediction_RF$RentalCount_Pred , model_name = "RF", threshold=50)


##########################################################################################################################################

##	Gradient Boosted Trees Scoring 

##########################################################################################################################################

# Make Predictions, then import them into R. The observed Conversion_Flag is kept through the argument extraVarsToWrite.
GBT_Scoring <- rxPredict(btree_model,data = train_dr_rent, overwrite = T, type="response",extraVarsToWrite = c("RentalCount"))

Prediction_GBT <- rxImport(inData = GBT_Scoring, stringsAsFactors = T, outFile = NULL)
observed <- Prediction_GBT$RentalCount

# Compute the performance metrics of the model.
Metrics_GBT <- evaluate_model(observed = observed, predicted_probability = Prediction_GBT$RentalCount_Pred, model_name = "GBT", threshold=50)


##########################################################################################################################################
## Select the best model based on AUC
##########################################################################################################################################

best <- ifelse(Metrics_RF$Accuracy >= Metrics_GBT$Accuracy, "RF", "GBT")

eval <- data.frame(acc= c(Metrics_RF$Accuracy, Metrics_GBT$Accuracy), modelname=c("RF", "GBT"))


## predicting

## serialize and unserialize
#model from query

trained_model <- as.raw(serialize(btree_model, connection=NULL))
btree_model_unserialized <- unserialize(trained_model)			

new_data <- data.frame(Year=2014, Month=5, Day=12, WeekDay=1, Holiday=0, Snow=0, RentalCount=0)

#prediction
prediction <- rxPredict(model=btree_model_unserialized,data = new_data, overwrite = TRUE, type="response",extraVarsToWrite = c("RentalCount"))
Prediction_New <- rxImport(inData = prediction, stringsAsFactors = T, outFile = NULL)

OutputDataSet <- data.frame(Prediction_new)



### unsupervised!

##########################
####     rxKmeans
##########################
set.seed(10)
head(dr_rent)

DF <- data.frame(dr_rent)
# and remove the Fholidays and Fsnow variables
DF <- DF[c(1,2,3,4,5,6,7)]

XDF <- paste(tempfile(), "xdf", sep=".")
if (file.exists(XDF)) file.remove(XDF)
rxDataStep(inData = DF, outFile = XDF)


# grab 2 random rows for starting 
#and remove holidays
centers <- DF[sample.int(NROW(DF), 10, replace = TRUE),] 

#create formula
#Formula =  ~ Year + Month + Day  + WeekDay + Snow + RentalCount + Holiday ##exclude holidays
Formula =  ~ Year + Month + Day + RentalCount + WeekDay + Holiday + Snow ##exclude holidays

# Example using an XDF file as a data source
rxKmeans(formula = Formula, data = XDF, centers = centers)
z <- rxKmeans(formula=Formula, data = DF, centers = centers)

rxKmeans(formula = Formula, data = XDF, numClusters=2)
, <- rxKmeans(formula=Formula, data = DF, numClusters=2)

zdf <- data.frame(z$centers)
names(zdf)

library("cluster")
clusplot(DF, z$cluster, color=TRUE, shade=TRUE, labels=4, lines=0, plotchar = TRUE)


#Determine number of clusters
#Using a plot of the within groups sum of squares, by number of clusters extracted, can help determine the appropriate number of clusters
#We are looking for a bend in the plot. It is at this "elbow" in the plot that we have the appropriate number of clusters
wss <- (nrow(DF) - 1) * sum(apply(DF, 2, var))
for (i in 2:20)
  wss[i] <- sum(kmeans(DF, centers = i)$withinss)
plot(1:20, wss, type = "b", xlab = "Number of Clusters", ylab = "Within groups sum of squares")

#recalculate with 3 clusters!
z3 <- rxKmeans(formula = Formula, data = DF, numClusters=3, outColName="cluster")
clusplot(DF, z3$cluster, color=TRUE, shade=TRUE, labels=4, lines=0, plotchar = TRUE)




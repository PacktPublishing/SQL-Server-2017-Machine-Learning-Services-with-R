##~~~~~~~~~~~~~~~~~~~~~~~
#  Chapter 2
#  Tomaz Kastrun
#
##~~~~~~~~~~~~~~~~~~~~~~~


setwd("C:\\DataTK")


# Matrix creation
set.seed (2908)
M <- 20000
n <- 100
Mat <- matrix (runif (M*n),M,n)


### Connect to CRAN R Engine ######

# Matrix multiply
system.time (
  Mat_MM <- Mat%*% t(Mat), gcFirst=TRUE
)[1]

# user.self 
# 26.69 

# Matrix multiply with crossprod
system.time (
  Mat_CP <- crossprod(Mat), gcFirst=TRUE
)[1]
# user.self 
# 0.19 


### Switch to MRAN R-Open Engine with MKL ######

# setMKLthreads(4) ## Optional

# Matrix multiply
system.time (
  Mat_MM <- Mat%*% t(Mat), gcFirst=TRUE
)[1]

# user.self 
# 2.75 

# Matrix multiply with crossprod
system.time (
  Mat_CP <- crossprod(Mat), gcFirst=TRUE
)[1]

# user.self 
# 0.01 



## Draw a graph

CRAN <- c(26.69, 2.75) 
MRAN <- c(0.19, 0.01)
MKL_Method <- c("MM", "CP")
df <- data.frame(cbind(CRAN,MRAN,MKL_Method))


library(reshape2)
df.long<-melt(df,id.vars="MKL_Method")


str(df.long)
df.long$value <- as.numeric(df.long$value)

library(ggplot2)

ggplot(df.long,aes(x=variable,y=value,fill=factor(MKL_Method)))+
  geom_bar(stat="identity",position="dodge")+
  scale_fill_discrete(name="variable",
                      breaks=c(1, 2),
                      labels=c("CRAN", "MRAN"))+
  xlab("Linear Algebra functions")+ylab("Time in seoconds")


#### Comparing packages

set.seed(6546)
nobs <- 1e+07
df <- data.frame("group" = as.factor(sample(1:1e+05, nobs, replace = TRUE)), "variable" = rpois(nobs, 100))
# ~ 5 seconds 10.000.000 rows; 100.000 groups

class(df) #[1] "data.frame"

format(object.size(df), units="auto")
str(df)

## TEST


# Calculate mean of variable within each group using plyr - ddply 
library(plyr)
system.time(grpmean <- ddply(
  df, 
  .(group), 
  summarize, 
  grpmean = mean(variable)
)
)

# user  system elapsed 
# 25.17    0.67   26.12 


# Calcualte mean of variable within each group using dplyr
detach("package:plyr", unload=TRUE)
library(dplyr)

system.time(
  grpmean2 <- df %>% 
    group_by(group) %>%
    summarise(group_mean = mean(variable))
)
# user  system elapsed 
# 1.93    0.06    2.00 


# Calcualte mean of variable within each group using data.table
library(data.table)
system.time(
  grpmean3 <- data.table(df)[
    #i
    ,mean(variable)   #j
    ,by=(group)]      #BY
)


# user  system elapsed 
# 0.32    0.03    0.34 


# Calcualte mean of variable within each group using sqldf
library(sqldf)
system.time(grpmean4 <- sqldf("SELECT avg(variable), [group] from df GROUP BY [group]"))

# user  system elapsed 
# 25.79    1.75   27.72 



#######################
#### END OF CODE #####
#######################







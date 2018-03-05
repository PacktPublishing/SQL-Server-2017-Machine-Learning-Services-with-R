
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


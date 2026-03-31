# Applied Data Science for BI Professionals and DBAs
# (c) Enrico van de Laar

# 1. Descriptive statistics
# -------------------------

# First of all we are going to import some data to work with
# In this case the data we are going to inspect is stored in a csv file
# so we can use the read.csv function to import the data
car_prices <- read.csv('autos.csv', stringsAsFactors = FALSE, header = TRUE, na.strings = 'NA' )

# Lets see how much data we loaded into our dataframe
nrow(car_prices)

# To see a bit about the data we just imported we can use the str() command
# this returns the structure of a R object
str(car_prices)

# Lets take a look at some of the descriptive statistics available in R
mean(car_prices$price)

# If there are NA values inside a column we cannot calculate anything
# For this reason we are going to remove the rows if a NA value is detected 
# in any column for that row
car_prices <-na.omit(car_prices)

# How much rows did we remove?
nrow(car_prices)

# Ok, now that we got the NA values taken care off, lets take a look at the
# descriptive statistics

# start with the mean
mean(car_prices$price)

# Median
median(car_prices$price)

# Minimum value
min(car_prices$price)

# Maximum value
max(car_prices$price)

# Variance
var(car_prices$price)

# Standard deviation
sd(car_prices$price)

# Another, faster, options is use the summary function
summary(car_prices$price)

# 2. Data distributions and visualization
# ---------------------------------------

# Creating a graph is extremly easy in R
plot(car_prices$price)

# Boxplots are very handy to visualize the spread of the data
boxplot(car_prices$price)

# Many of our prices are concentrated in the lower price range
# This suggests our data is skewed-right
# Lets see with a histogram
hist(car_prices$price)

# The are more forms of data distribution
# Like a normal distribution
hist(rbeta(10000,5,5))

# Or a left-skewed distribution
hist(rbeta(10000,5,2))

# Even though the default visualizations look pretty decent
# there are packages that give us way more graphical power
# install.packages("ggplot2")
library(ggplot2)

# qplot stands for quick plot in ggplot2
qplot(car_prices$price)

# Lets do something fancier where we do not have a histogram as default
g <- ggplot(car_prices, aes(horsepower, price))
g + geom_jitter(width = .5, size=1) +
  labs(y="Price", 
       x="Horsepower", 
       title="Car price vs horsepower")

# 3. Finding relations in our data
# --------------------------------

# R has a build-in function to detect correolation between features
# In this case we measure the corrolation between the price and weight of a car
# The close the number is to 1 (or -1) the higher the corrolation between features
cor(car_prices$curb.weight, car_prices$price)

# Let's plot both the features in a scatterplot
# Notice that when the weight goes up the price does as well
plot(car_prices$curb.weight, car_prices$price, xlab = 'Weight', ylab = 'price')

# On thing to keep in mind is that the cor fucntion can only handle numeric features
# So we have to filter the non-numeric features out if we want to look at
# corrolations in the entire data frame
cor(car_prices[,c(1,2,3,10,11,12,13,14,17,19:26)])

# These lists of corrolations can be difficult to read so let's visualize it
# One nice method is using a heatmap to show corrolation between features
library(reshape2)

# Let's make a corrolation matrix first
# We are filtering out all the non-numeric features using another method: is.numeric
cor_matrix <- cor(car_prices[sapply(car_prices, is.numeric)])

# Melt the matrix to a table (wide) format
melted_cor_matrix <- melt(cor_matrix)

# Plot a heatmap of the correlation table
ggplot(data = melted_cor_matrix, aes(x=Var1, y=Var2, fill=value)) + 
  geom_tile() +
  geom_text(aes(Var2, Var1, label = round(value, digits=2)), color = "black", size = 4) +
  theme(axis.title.x=element_blank(),
        axis.ticks.x=element_blank(),
        axis.title.y=element_blank(),
        axis.ticks.y=element_blank())

# 4. Building statistical models - Simple Linear regression
# --------------------------------------------------

# install.packages("dplyr")
library(dplyr)

# In the data we have so far we looked at the relation between price and other
# features. Let's see if we can predict the price of a car.
# Since the price is a numerical feature we are going to use regression methods

# Let's look at the scatterplot of car price vs curb weight again
plot(car_prices$curb.weight, car_prices$price, xlab = 'Weight', ylab = 'price')

# And the corrolation between them
cor(car_prices$price, car_prices$curb.weight)

# Let's build a simple linear model
lin_mod <- lm(car_prices$price ~ car_prices$curb.weight, data = car_prices)

# Look at the results of the model
lin_mod

# The Intercepts shows the value of the price when the curb_weight is zero
# The Coefficients tell us by how much the price goes up by an increase of 1 in the feature
# In this case for every increase of 1 in weight, the price goes up by $10.97

# How does simple regression work?
# The formula is: y = a + Bx
# y is the value we want to predict
# a = intercept (-15540,67)
# B = coefficient (10,97)
# x = value of the row 

# For example, consider a car with a weight of 2337
# y = -15540,67 + (2337*10,97) 
# y = 10.096,22

# Let's look at this visually, the abline function add a line to the plot based on the
# intercept and coefficients of the linear model
with(car_prices,plot(curb.weight, price, xlab = 'Weight', ylab = 'price'))
abline(lin_mod, col="red")

# Add in our manually calculate data point
points(2337, 10096.22, col="red", pch=19)

# To find out how good our model performs we can use the summary function
summary(lin_mod)

# Let's move through the summary one step at a time
# The Residuals tell us how much error there was in our predictions
# as you can see there were some pretty big error values but most predictions 
# fall between the -1415 and 1129 range (1Q and 3Q)

# We can plot/inspect this information when we look at the results of the data inside the summary function.
# All the data it returns is stored in a list object
lin_mod_sum <- summary(lin_mod)
boxplot(lin_mod_sum$residuals)

# Back to the summary again
summary(lin_mod)

# The stars indicate the significance.
# It's common to look for a significance level of 0.05 to denote a statistically significant parameter
# Here we see the curb.weight is very significant

# The residual standard error shows the difference between the actual values and the regression line
# The R-squared value shows us how much of the variablility of the data we are explaining through the model
# the higher this value the better

# So can we use the model to predict the price of a car based on the curb weight?
lin_mod_predict <- predict(lin_mod, car_prices)

# Add the car_prices and the predicted prices to a new data frame
car_prices_lm <- cbind(car_prices, predicted.price = lin_mod_predict)

# Let's look at the first 5 rows
head(car_prices_lm)

# Let's see how we did with our predicting for a car with a weight of 2337
# In this case we are using dplyr to filter based on a value in a row
pred_2337_car <- filter(car_prices_lm, curb.weight == 2337)
pred_2337_car$predicted.price

# Let's make a plot with all the fitted and actual prices
plot_col <- c('black','red')
plot(car_prices$price, fitted(lin_mod),col=plot_col)


# 5. Building statistical models - Multiple Linear regression
# ----------------------------------------------------------

# So far we only build a linear model with one single feature
# We can, ofcourse, also build a model with multiple, numerical, features
# Notice the interaction notation between engine.size and curb.weight
lin_mod_mult <- lm(price ~ length + width + engine.size*curb.weight + horsepower , data = car_prices)

# Lets look at the summary
summary(lin_mod_mult)

# Visualizing the results between multiple predictor features 
# and a single response is complex since it requires a 3D graph


# 6. Building statistical models - Binary Classification
# --------------------------------------------------

# Import the credit dataset that shows if loans default or not
credit <- read.csv("credit.csv", header = TRUE)

# Modify the data a bit so we get a character back instead of a numerical value
# to indicate a default
credit$default[credit$default==1] <- "no"
credit$default[credit$default==2] <- "yes"
credit$default <- as.factor(credit$default)

# First thing we do, look at the data!
str(credit)
head(credit)

# Plot the feature we are going to classify
plot(credit$default)

# One very powerful method of building a classification model is trough decision trees
# installed.packages("rpart")
# install.packages("rpart.plot")
# install.packages("caret")
# install.packages("e1071")
# install.packages("ROCR")

library(rpart)
library(rpart.plot)
library(caret)
library(e1071)
library(ROCR)

# We are going to split our data so we can measure how good our model performs
# For this we divide 75% of our data in a training dataset and the remaining in a test dataset

# We are setting a seed to we get the same split every time we run the code
set.seed(1234) 

# Now Selecting 75% of data as sample from total 'n' rows of the data  
smp_size <- floor(0.75 * nrow(credit))
train_ind <- sample(seq_len(nrow(credit)), size = smp_size)

# Create two new dataframes for training and testing
credit_train <- credit[train_ind, ]
credit_test <- credit[-train_ind, ]

# Let's see if we neatly split the data
nrow(credit)
nrow(credit_train)
nrow(credit_test)

# Let's build a decision tree to determine if a loan will default on all features
# in the credit dataset on the data in the test dataset
tree_model <- rpart(default ~., data=credit_train, method="class")

# One advantage of trees are that they are easy to interpret
# The rpart.plot library can easily return the tree layout
rpart.plot(tree_model)

# Now let's see how our tree performs on the data it has never seen in the test dataset
credit_pred <- predict(tree_model, newdata = credit_test, type = "class")

# To measure how "good" a classification model performs we can use a confusion matrix
confusionMatrix(credit_pred, credit_test$default)

# Confusion matrixes come with different types of errors
# Type I error / False Positive: We predict positive but true value was negative
# type II error / False Negative: We predict negative but true value was positive

# 7. Building statistical models - Clustering
# --------------------------------------------------

# In this example we are going to see if we can group wines together based on characteristics

# install.packages("cluster")
# install.packages("flexclust")
library(cluster)
library(flexclust)

# Import the csv
wine <- read.csv("wine.csv", header = TRUE)
head(wine)

# We need to "scale" the measurements before we use K-means to make sure there is a good measure
# of distance between the cluster centers
# We are also removing the "type" column
wine_scaled <- scale(wine[,-1])
head(wine_scaled)

# Let's build a cluster model based on k-means
# In this example we choose 2 cluster centers
fit <- kmeans(wine_scaled, 2)

# Plot the clusters
clusplot(wine, fit$cluster, color=TRUE, shade=TRUE, labels=1, lines=0)

# Setting the number of clusters is the most important setting when using k-means
# In this case you want to pay attention to detect the right value for k
# The script below will automatically run kmeans a number of times and return a 
# plot from which you can detect a good cluster amount (elbow method)
rng<-2:20 #K from 2 to 20
tries <-100 #Run the K Means algorithm 100 times
avg.totw.ss <-integer(length(rng)) #Set up an empty vector to hold all of points
for(v in rng){ # For each value of the range variable
  v.totw.ss <-integer(tries) #Set up an empty vector to hold the 100 tries
  for(i in 1:tries){
    k.temp <-kmeans(wine_scaled,centers=v) #Run kmeans
    v.totw.ss[i] <-k.temp$tot.withinss #Store the total withinss
  }
  avg.totw.ss[v-1] <-mean(v.totw.ss) #Average the 100 total withinss
}
plot(rng,avg.totw.ss,type="b", main="Total Within SS by Various K",
     ylab="Average Total Within Sum of Squares",
     xlab="Value of K",
     xaxt="n")
axis(1, at=seq(1, 20, by = 1), las=2)

# According to the line graph a setting of 3 seems to be the best value
fit <- kmeans(wine_scaled, 3)

# Plot the clusters
clusplot(wine, fit$cluster, color=TRUE, shade=TRUE, labels=1, lines=0)

# how well did the clusters fit?
# We are creating a table with the orginal wine type and the cluster allocation through k-means
clus_table <- table(wine$type, fit$cluster)

# Compare the cluster assignments -1 is no agreement, 1 perfect agreement
randIndex(clus_table)

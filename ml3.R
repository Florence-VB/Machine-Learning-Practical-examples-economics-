setwd("I://fbs//ML")

# Installs packages if not already installed, then loads packages 
list.of.packages <- c("glmnet", "rpart", "rpart.plot", "randomForest", "devtools", "tidyverse", "knitr", "SuperLearner", "caret", "xgboost")
new.packages <- list.of.packages[!(list.of.packages %in% installed.packages()[,"Package"])]
if(length(new.packages)) install.packages(new.packages, repos = "http://cran.us.r-project.org")

invisible(lapply(list.of.packages, library, character.only = TRUE))

# install causalTree package from Susan Athey's github
install_github('susanathey/causalTree')
library(causalTree)

select <- dplyr::select

# Set seed for reproducibility
set.seed(1)
# Load data
my_data <- readRDS('social_voting.rds')

# Restrict the sample size
n_obs <- 33000 # Change this number depending on the speed of your computer. 6000 is also fine. 
my_data <- my_data[sample(nrow(my_data), n_obs), ]

# Split data into 3 samples
folds = createFolds(1:nrow(my_data), k=3)

Y1 <- my_data[folds[[1]],1]
Y2 <- my_data[folds[[2]],1]
Y3 <- my_data[folds[[3]],1]

X1 <- my_data[folds[[1]],2]
X2 <- my_data[folds[[2]],2]
X3 <- my_data[folds[[3]],2]

W1 <- my_data[folds[[1]],3:ncol(my_data)]
W2 <- my_data[folds[[2]],3:ncol(my_data)]
W3 <- my_data[folds[[3]],3:ncol(my_data)]

### Creates a vector of 0s and a vector of 1s of length n (hack for later usage)
zeros <- function(n) {
  return(integer(n))
}
ones <- function(n) {
  return(integer(n)+1)
}



sl_lm = SuperLearner(Y = Y1, 
                     X = data.frame(X=X1, W1, W1*X1), 
                     family = binomial(), 
                     SL.library = "SL.lm", 
                     cvControl = list(V=0))

summary(sl_lm$fitLibrary$SL.lm_All$object)
ols_pred_0s <- predict(sl_lm, data.frame(X=zeros(nrow(W2)), W2, W2*zeros(nrow(W2))), onlySL = T)
ols_pred_1s <- predict(sl_lm, data.frame(X=ones(nrow(W2)), W2, W2*ones(nrow(W2))), onlySL = T)

cate_ols <- ols_pred_1s$pred - ols_pred_0s$pred


lasso = create.Learner("SL.glmnet", params = list(alpha = 1), name_prefix="lasso")

get_lasso_coeffs <- function(sl_lasso) {
  return(coef(sl_lasso$fitLibrary$lasso_1_All$object, s="lambda.min")[-1,])
}  

SL.library <- lasso$names
predict_y_lasso <- SuperLearner(Y = Y1,
                                X = data.frame(X=X1, W1, W1*X1), 
                                family = binomial(),
                                SL.library = SL.library, 
                                cvControl = list(V=0))

kept_variables <- which(get_lasso_coeffs(predict_y_lasso)!=0)

predict_x_lasso <- SuperLearner(Y = X1,
                                X = data.frame(W1), 
                                family = binomial(),
                                SL.library = lasso$names, 
                                cvControl = list(V=0))

kept_variables2 <- which(get_lasso_coeffs(predict_x_lasso)!=0) + 1 #+1 to include X

sl_post_lasso <- SuperLearner(Y = Y1,
                              X = data.frame(X=X1, W1, W1*X1)[, c(kept_variables, kept_variables2)], 
                              family = binomial(),
                              SL.library = "SL.lm", 
                              cvControl = list(V=0))

summary(sl_post_lasso$fitLibrary$SL.lm_All$object)
####comparing estimations for W2, X2, X3 etc... instabilitz of results


postlasso_pred_0s <- predict(sl_post_lasso, data.frame(X=zeros(nrow(W2)), W2, W2*zeros(nrow(W2)))[, c(kept_variables, kept_variables2)], onlySL = T)
postlasso_pred_1s <- predict(sl_post_lasso, data.frame(X=ones(nrow(W2)), W2, W2*ones(nrow(W2)))[, c(kept_variables, kept_variables2)], onlySL = T)

cate_postlasso <- postlasso_pred_1s$pred - postlasso_pred_0s$pred



#Get formula
tree_fml <- as.formula(paste("Y", paste(names(W1), collapse = ' + '), sep = " ~ "))

### causal tree
causal_tree <- causalTree(formula = tree_fml,
                          data = data.frame(Y=Y1, W1),
                          treatment = X1,
                          split.Rule = "CT", #causal tree
                          split.Honest = F, #will talk about this next
                          split.alpha = 1, #will talk about this next
                          cv.option = "CT",
                          cv.Honest = F,
                          split.Bucket = T, #each bucket contains bucketNum treated and bucketNum control units
                          bucketNum = 5, 
                          bucketMax = 100, 
                          minsize = 250) # number of observations in treatment and control on leaf

rpart.plot(causal_tree, roundint = F) #returns the trees 

###modified trees with bucket parameters
###increased number of min size and the number, max of bucets
causal_tree <- causalTree(formula = tree_fml,
                          data = data.frame(Y=Y1, W1),
                          treatment = X1,
                          split.Rule = "CT", #causal tree
                          split.Honest = F, #will talk about this next
                          split.alpha = 1, #will talk about this next
                          cv.option = "CT",
                          cv.Honest = F,
                          split.Bucket = T, #each bucket contains bucketNum treated and bucketNum control units
                          bucketNum = 10, 
                          bucketMax = 70, 
                          minsize = 300) # number of observations in treatment and control on leaf

rpart.plot(causal_tree, roundint = F) #returns the trees 



causal_tree <- causalTree(formula = tree_fml,
                          data = data.frame(Y=Y1, W1),
                          treatment = X1,
                          split.Rule = "CT", #causal tree
                          split.Honest = F, #will talk about this next
                          split.alpha = 1, #will talk about this next
                          cv.option = "CT",
                          cv.Honest = F,
                          split.Bucket = T, #each bucket contains bucketNum treated and bucketNum control units
                          bucketNum = 2, 
                          bucketMax = 150, 
                          minsize = 100) # number of observations in treatment and control on leaf

rpart.plot(causal_tree, roundint = F) #return

#####
###honnest trrees
honest_tree <- honest.causalTree(formula = tree_fml,
                                 data = data.frame(Y=Y1, W1),
                                 treatment = X1,
                                 est_data = data.frame(Y=Y2, W2),
                                 est_treatment = X2,
                                 split.alpha = 0.5,
                                 split.Rule = "CT",
                                 split.Honest = T,
                                 cv.alpha = 0.5,
                                 cv.option = "CT",
                                 cv.Honest = T,
                                 split.Bucket = T,
                                 bucketNum = 5,
                                 bucketMax = 100, # maximum number of buckets
                                 minsize = 250) # number of observations in treatment and control on leaf

rpart.plot(honest_tree, roundint = F)

###CV to determine the best models and related var selection
opcpid <- which.min(honest_tree$cp[, 4]) 
opcp <- honest_tree$cp[opcpid, 1]
honest_tree_prune <- prune(honest_tree, cp = opcp)

rpart.plot(honest_tree_prune, roundint = F)


###
### there will be an error here if your pruned tree has no leaves
leaf2 <- as.factor(round(predict(honest_tree_prune,
                                 newdata = data.frame(Y=Y2, W2),
                                 type = "vector"), 4))

# Run linear regression that estimate the treatment effect magnitudes and standard errors
honest_ols_2 <- lm( Y ~ leaf + X * leaf - X -1, data = data.frame(Y=Y2, X=X2, leaf=leaf2, W2))

summary(honest_ols_2)

######to be re run on subsample 3 to check if results hold 
honest_tree3 <- honest.causalTree(formula = tree_fml,
                                 data = data.frame(Y=Y1, W1),
                                 treatment = X1,
                                 est_data = data.frame(Y=Y3, W3),
                                 est_treatment = X3,
                                 split.alpha = 0.5,
                                 split.Rule = "CT",
                                 split.Honest = T,
                                 cv.alpha = 0.5,
                                 cv.option = "CT",
                                 cv.Honest = T,
                                 split.Bucket = T,
                                 bucketNum = 5,
                                 bucketMax = 100, # maximum number of buckets
                                 minsize = 250) # number of observations in treatment and control on leaf

rpart.plot(honest_tree3, roundint = F)

###CV to determine the best models and related var selection
opcpid <- which.min(honest_tree3$cp[, 4]) 
opcp <- honest_tree3$cp[opcpid, 1]
honest_tree_prune3 <- prune(honest_tree3, cp = opcp)

rpart.plot(honest_tree_prune, roundint = F)
### there will be an error here if your pruned tree has no leaves
leaf3 <- as.factor(round(predict(honest_tree_prune3,
                                 newdata = data.frame(Y=Y3, W3),
                                 type = "vector"), 4))

# Run linear regression that estimate the treatment effect magnitudes and standard errors
honest_ols_3 <- lm( Y ~ leaf + X * leaf - X -1, data = data.frame(Y=Y3, X=X3, leaf=leaf3, W3))

summary(honest_ols_3)
cate_honesttree <- predict(honest_tree_prune, newdata = data.frame(Y=Y2, W2), type = "vector")
print(cate_honesttree)

###causal forest
# Causal forests 
causalforest <- causalForest(tree_fml,
                             data=data.frame(Y=Y1, W1), 
                             treatment=X1, 
                             split.Rule="CT", 
                             split.Honest=T,  
                             split.Bucket=T, 
                             bucketNum = 5,
                             bucketMax = 100, 
                             cv.option="CT", 
                             cv.Honest=T, 
                             minsize = 2, 
                             split.alpha = 0.5, 
                             cv.alpha = 0.5,
                             sample.size.total = floor(nrow(Y1) / 2), 
                             sample.size.train.frac = .5,
                             mtry = ceiling(ncol(W1)/3), 
                             nodesize = 5, 
                             num.trees = 10, 
                             ncov_sample = ncol(W1), 
                             ncolx = ncol(W1))
cate_causalforest <- predict(causalforest, newdata = data.frame(Y=Y2, W2), type = "vector")
#outcomes of CATE for all var



## Compare Heterogeneity
het_effects <- data.frame(ols = cate_ols, 
                          post_selec_lasso = cate_postlasso, 
                          causal_tree = cate_honesttree, 
                          causal_forest = cate_causalforest)

# Set range of the x-axis
xrange <- range( c(het_effects[, 1], het_effects[, 2], 
                  het_effects[, 3], 
                   het_effects[, 4]))

# Set the margins (two rows, three columns)
par(mfrow = c(2, 3)) #4

hist(het_effects[, 1], main = "OLS", xlim = xrange)
hist(het_effects[, 2], main = "Post-selection Lasso", xlim = xrange)
hist(het_effects[, 3], main = "Causal tree", xlim = xrange)
hist(het_effects[, 4], main = "Causal forest", xlim = xrange)

###best predictors
blp <- function(Y, W, X, prop_scores=F) {
  
  ### STEP 1: split the dataset into two sets, 1 and 2 (50/50)
  split <- createFolds(1:length(Y), k=2)[[1]]
  
  Ya = Y[split]
  Yb = Y[-split]
  
  Xa = X[split]
  Xb = X[-split]
  
  Wa = W[split, ]
  Wb = W[-split, ]
  
  ### STEP 2a: (Propensity score) On set A, train a model to predict X using W. Predict on set B.
  if (prop_scores==T) {
    sl_w1 = SuperLearner(Y = Xa, 
                         X = Wa, 
                         newX = Wb, 
                         family = binomial(), 
                         SL.library = "SL.xgboost", 
                         cvControl = list(V=0))
    
    p <- sl_w1$SL.predict
  } else {
    p <- rep(mean(Xa), length(Xb))
  }
  
  ### STEP 2b let D = W(set B) - propensity score.
  D <- Xb-p
  
  ### STEP 3a: Get CATE (for example using xgboost) on set A. Predict on set B.
  sl_y = SuperLearner(Y = Ya, 
                      X = data.frame(X=Xa, Wa), 
                      family = gaussian(), 
                      SL.library = "SL.xgboost", 
                      cvControl = list(V=0))
  
  pred_y1 = predict(sl_y, newdata=data.frame(X=ones(nrow(Wb)), Wb))
  
  pred_0s <- predict(sl_y, data.frame(X=zeros(nrow(Wb)), Wb), onlySL = T)
  pred_1s <- predict(sl_y, data.frame(X=ones(nrow(Wb)), Wb), onlySL = T)
  
  cate <- pred_1s$pred - pred_0s$pred
  
  ### STEP 3b: Subtract the expected CATE from the CATE
  C = cate-mean(cate)
  
  ### STEP 4: Create a dataframe with Y, W (set B), D, C and p. Regress Y on W, D and D*C. 
  df <- data.frame(Y=Yb, Wb, D, C, p)
  
  Wnames <- paste(colnames(Wb), collapse="+")
  fml <- paste("Y ~",Wnames,"+ D + D:C")
  model <- lm(fml, df, weights = 1/(p*(1-p))) 
  
  return(model) 
}

table_from_blp <-function(model) {
  thetahat <- model%>% 
    .$coefficients %>%
    .[c("D","D:C")]
  
  # Confidence intervals
  cihat <- confint(model)[c("D","D:C"),]
  
  res <- tibble(coefficient = c("beta1","beta2"),
                estimates = thetahat,
                ci_lower_90 = cihat[,1],
                ci_upper_90 = cihat[,2])
  
  return(res)
}
output <- rerun(10, table_from_blp(blp(Y1, W1, X1))) %>% # Increase reruns in practice!
  bind_rows %>%
  group_by(coefficient) %>%
  summarize_all(median)

output
########################################################
gates <- function(Y, W, X, Q=4, prop_scores=F) {
  
  ### STEP 1: split the dataset into two sets, 1 and 2 (50/50)
  split <- createFolds(1:length(Y), k=2)[[1]]
  
  Ya = Y[split]
  Yb = Y[-split]
  
  Xa = X[split]
  Xb = X[-split]
  
  Wa = W[split, ]
  Wb = W[-split, ]
  
  ### STEP 2a: (Propensity score) On set A, train a model to predict X using W. Predict on set B.
  if (prop_scores==T) {
    sl_w1 = SuperLearner(Y = Xa, 
                         X = Wa, 
                         newX = Wb, 
                         family = binomial(), 
                         SL.library = "SL.xgboost", 
                         cvControl = list(V=0))
    
    p <- sl_w1$SL.predict
  } else {
    p <- rep(mean(Xa), length(Xb))
  }
  
  ### STEP 2b let D = W(set B) - propensity score.
  D <- Xb-p
  
  ### STEP 3a: Get CATE (for example using xgboost) on set A. Predict on set B.
  sl_y = SuperLearner(Y = Ya, 
                      X = data.frame(X=Xa, Wa), 
                      family = gaussian(), 
                      SL.library = "SL.xgboost", 
                      cvControl = list(V=0))
  
  pred_y1 = predict(sl_y, newdata=data.frame(X=ones(nrow(Wb)), Wb))
  
  pred_0s <- predict(sl_y, data.frame(X=zeros(nrow(Wb)), Wb), onlySL = T)
  pred_1s <- predict(sl_y, data.frame(X=ones(nrow(Wb)), Wb), onlySL = T)
  
  cate <- pred_1s$pred - pred_0s$pred
  
  ### STEP 3b: divide the cate estimates into Q tiles, and call this object G. 
  # Divide observations into n tiles
  G <- data.frame(cate) %>% # replace cate with the name of your predictions object
    ntile(Q) %>%  # Divide observations into Q-tiles
    factor()
  
  ### STEP 4: Create a dataframe with Y, W (set B), D, G and p. Regress Y on group membership variables and covariates. 
  df <- data.frame(Y=Yb, Wb, D, G, p)
  
  Wnames <- paste(colnames(Wb), collapse="+")
  fml <- paste("Y ~",Wnames,"+ D:G")
  model <- lm(fml, df, weights = 1/(p*(1-p))) 
  
  return(model) 
}
table_from_gates <-function(model) {
  thetahat <- model%>% 
    .$coefficients %>%
    .[c("D:G1","D:G2","D:G3","D:G4")]
  
  # Confidence intervals
  cihat <- confint(model)[c("D:G1","D:G2","D:G3","D:G4"),]
  
  res <- tibble(coefficient = c("gamma1","gamma2","gamma3","gamma4"),
                estimates = thetahat,
                ci_lower_90 = cihat[,1],
                ci_upper_90 = cihat[,2])
  
  return(res)
}

output <- rerun(10, table_from_gates(gates(Y1, W1, X1))) %>% # Increase reruns in practice!
  bind_rows %>%
  group_by(coefficient) %>%
  summarize_all(median)

output

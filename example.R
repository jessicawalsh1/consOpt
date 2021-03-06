library(ompr)
library(ompr.roi)
library(ROI.plugin.lpsolve)
library(magrittr)
source('plotutil.R')
source('debugging.R')

# Load in and prepare the data
# ----------------------------

Bij_fre_01 <- read.csv("testdata2/Bij_fre_01.csv")
cost_fre_01 <- read.csv("testdata2/cost_fre_01.csv")

# Prep benefits 
rownames(Bij_fre_01) <- Bij_fre_01$X
Bij_fre_01$X <- NULL

# Prep costs 
cost.vector <- cost_fre_01$Cost

# ------------------------------
# TESTING SHIT
# ------------------------------

#' Optimization proceeds from a bespoke optimization object (optStruct) holding all the data and functionality.
#' Most of it will not be user-facing, but until it gets wrapped in something easy to use, let's test
#' the individual bits and pieces 

# Initialize the optimization object for threshold=60.01
testOpt60 <- optStruct$new(B=Bij_fre_01,
                           cost.vector=cost.vector,
                           all.index=15,
                           t=60.01)

#' The creation of the optStruct takes care of thresholding and various manipulations to do with the baseline,
#' as well as preparing the benefits matrix for computation (rounding etc.)

# Initialize the optimization object for threshold=50.01
testOpt50 <- optStruct$new(B=Bij_fre_01,
                           cost.vector=cost.vector,
                           all.index=15,
                           t=50.01)

#' The optimization object has a solve() method which accepts a budget, allowing for once-off runs of the ILP. 

# Get the S4+S5 strat for 50% 
res50 <- testOpt50$solve(budget=5657184)


#' Each optStruct object enables the addition of strategy combinations. This can, for instance, be adding information about
#' strategies already in the benefits matrix - like the following, which combines strategies S12 and S13 by making explicit
#' which strategies they each are composed of. This information is supplied using the add.combo() method of the optStruct object,
#' which requires strategy information as named lists like so:
input <- list(strat1="S12", strat2="S13")
output <- list(strat1=c("S3", "S7", "S10"), strat2=c("S6", "S9", "S10"))
#' The actual lists are added with a function call:
testOpt60$add.combo(input.strategies = input, combined.strategies = output)
#' One can also define novel strategy combinations by inputting a single strategy with a value of NULL, 
#' and outputting a list of strategies currently in the benefits matrix.
testOpt60$add.combo(input.strategies = list(strat1=NULL), combined.strategies=list(strat1= c("S1", "S2"))) # will have the name "S1 + S2"


# ------------------------------
# Optimizing over a range of budgets and thresholds
# ------------------------------

#' Optimizing over a range of thresholds requires creating/thresholding the benefits matrix a number of times
#' As such, the combo information has to be carried in a particular way for this to work. Currently this is implemented with a simple container object
#' which essentially sidesteps some quirks of R's list indexing. The user creates an empty "combination" object like so:
combo <- combination$new()
# And adds (any number of) combinations by calling add.combo()
combo$add.combo(input, output) # Add the S12+S13 

# The combination object is then passed to the optimize.range() function as an argument. If this argument is NULL (or just not supplied),
# no combo information is added. 
test.range <- optimize.range(Bij_fre_01, cost.vector, all.index = 15, combo.strategies = combo)

# Plotting the results is straightforward, as much of the work is done 
neat.plot(test.range)

# ------------------------------
# Testing the weighting function
# ------------------------------

Species_weight <- read.csv("testdata2/Species_weight.csv")
# Notice that the weights must be in exactly the same order as the species in the benefit matrix
# I can add stuff to automatically ensure this, but it's a lot of work so currently you're on your own
weights <- Species_weight$Weight


# Test if generic optimization objects are correctly constructed
testOpt60Weighted <- optStruct$new(B=Bij_fre_01,
                           cost.vector=cost.vector,
                           all.index=15,
                           t=60.01, 
                           weights = weights)

# Test if we can optimize over a range of budgets and thresholds
test.range.weighted <- optimize.range(
  B = Bij_fre_01,
  cost.vector = cost.vector,
  all.index = 15,
  weights = weights
)

neat.plot(test.range.weighted)


# ------------------------------
# Test combinations
# ------------------------------

COMBO_info <- read.csv("testdata2/COMBO_info.csv")
combos <- parse.combination.matrix(COMBO_info)
test.range <- optimize.range(Bij_fre_01, cost.vector, all.index = 15, combo.strategies = combos)
neat.plot(test.range)


#------------------------------------------
# Test combinations and weights
#------------------------------------------

test.range.weighted.combos <- optimize.range(
  B = Bij_fre_01, 
  cost.vector = cost.vector, 
  all.index = 15, 
  combo.strategies = combos,
  weights = weights
)

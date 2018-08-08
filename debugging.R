library(ompr)
library(ompr.roi)
library(ROI.plugin.lpsolve)
library(magrittr)
library(R6)
# ------------------------------
# Container object
# ------------------------------

optStruct <- R6Class("optStruct", 
  public = list(
    B = NULL,
    cost.vector = NULL,
    all.index = NULL,
    t = NULL,
    budget.max = NULL,
    weights = NULL,
    
    get.baseline.results = function(){
      #' Returns the "results" from only running the baseline strategy
      #'
      #' @return A list holding the results
      return( private$baseline.results )
    },
    
    add.combo = function(input.strategies, combined.strategies){
      #' The benefits matrix might contain strategies which are combinations of several strategies. The joint selection of these strategies
      #' will be artificially expensive if two combo strategies contain one or more of the same individual strategy, as the cost will be doubled
      #' E.g.: Strategy S12 is a combination of strategies S3, S7, and S10.
      #'       Strategy S13 is a combination of strategies S6, S9, and S10
      #' Selecting strategies S12 and S13 simultaneously will erronously count the cost of S10 twice, making this combination less favorable to the objective function.
      #' 
      #'  
      #' @param input.strategies A named list denoting strategy names, e.g. list(strategy1="S1", strategy2="S2", ...)
      #' @param combined.strategies A list of lists denoting strategy names that are combined, e.g. list(strategy1=c("S5", "S6", "S7"), strategy2=c("S6", "S7", "S8"))
      #' 
      #' @return Silently updates the benefits matrix and the cost vector
      #' 
      #' @example
      #' TODO

      if ( length(names(input.strategies)) < 1){
        stop("Error: input.strategies must be a named list")
      }
      
      if ( length(names(combined.strategies)) < 1){
        stop("Error: combined.strategies must be a named list")
      }
      
     
      input.strategy.names <- unlist(input.strategies, use.names=F)
      combined.strategy.names <- unlist(combined.strategies, use.names=F)
      
      # Check if the user supplied two (or more) existing strategies to combine 
      if (length(input.strategy.names) > 1){
        # Strategies must be in the benefits matrix to be combined
        if (!all(input.strategy.names %in% rownames(self$B))){
          stop("User supplied multiple strategies to combine, but they were not found in the benefits matrix")
        }
        
        # Both strategies are present, compute the cost vector correctly
        combined.strategy.names <- unlist(combined.strategies, use.names=F)
        applied.strategies <- union(combined.strategy.names, combined.strategy.names)
        # Make sure strategies are in the cost vector 
        if (!all(applied.strategies %in% names(self$cost.vector))){
          stop("Some strategies to be combined were not in the cost vector")
        }
        total.cost <- sum(self$cost.vector[applied.strategies])
        # Add cost to cost vector
        strategy.name <- paste(input.strategy.names, collapse=" + ")
        self$cost.vector <- c(self$cost.vector, total.cost)
        names(self$cost.vector)[length(self$cost.vector)] <- strategy.name
        # Add to benefits matrix - new species benefit vector is the logical OR of the benefit vectors of each input strategy
        old.benefits <- self$B[input.strategy.names,]
        new.row <- apply(old.benefits, 2, max) # take the max (1) of each column - same as (x['S2',] | x['S1',] )*1 for two rows
        self$B <- rbind(self$B, new.row)
        l <- length(rownames(self$B))
        rownames(self$B)[l] <- strategy.name
        
        # Done
        invisible(self)
      } else {
       # User supplied ONE strategy name as input, adding a novel strategy to the mix
        union.strategy.names <- union(combined.strategy.names, combined.strategy.names)
        if (!all(union.strategy.names %in% rownames(self$B))){
          stop("Error: User attempted to combine strategies that were not in the benefits matrix")
        }
        
        if (!all(union.strategy.names) %in% names(self$cost.vector)){
          stop("Error: User attempted to combine strategies that were not in the cost vector")
        }
        if (is.null(input.strategy.names)) {
          warning("No strategy name supplied, setting default name")
          default.strategy.name <- paste(union.strategy.names, collapse=" + ")
        } else {
          default.strategy.name <- input.strategy.names
        }
        
        # Compute cost
        total.cost <- sum(self$cost.vector[union.strategy.names])
        self$cost.vector <- c(self$cost.vector, total.cost)
        names(self$cost.vector)[length(self$cost.vector)] <- default.strategy.name
        # Compute benefits 
        old.benefits <- self$B[union.strategy.names,]
        new.row <- apply(old.benefits, 2, max)
        self$B <- rbind(self$B, new.row)
        l <- length(rownames(self$B))
        rownames(self$B)[l] <- default.strategy.name
        invisible(self)
      }
    },
    
    weight.species = function(weights){
      #'
      #'
      # TODO
    },
    
    solve = function(budget, debug=FALSE){
      #' Solve the ILP for this optStruct and a supplied budget
      #' 
      #' @param budget A number
      #' @return A result container
      
      if (budget == 0){
        return(self$get.baseline.results())
      }
      res <- private$solve.ilp(budget)
      parsed <- private$parse.results(res)
      if(debug){
        return(res)
      }
      parsed
    },

    initialize = function(B, cost.vector, all.index, t, weights=NULL){
      # TODO: Add error handling if parameters are missing
      self$B <- B
      self$cost.vector <- cost.vector
      self$all.index <- all.index
      self$t <- t
      names(self$cost.vector) <- rownames(self$B)
      # Check for names and do the rounding of B
      private$prepare()
      # Threshold B
      private$threshold(self$t)
      # Count the baseline results and remove etc.
      private$baseline.prep()
      # We are now ready to do optimization
    } 
  ),
  private = list(
    current.budget = NULL,
    baseline.idx = 1,
    baseline.results = NULL,
    species.buffer = list(),
    state = list(
      weighted = FALSE
    ),

    prepare = function(){
      #' Rounds the B matrix, check if B is labelled
      #'
      #' @return Updates self$B 
      self$B <- round(self$B, digits=2)

      strategy.names <- rownames(self$B)
      species.names <- colnames(self$B)

      if (length(strategy.names) < nrow(self$B) || length(species.names) < ncol(self$B))
        warning("Warning: Missing strategy or species label information, results will not be meaningful")
      names(self$cost.vector) <- strategy.names
      invisible(self)
    },

    threshold = function(t){
      #' Thresholds the B matrix, binarizing the entries
      #' 
      #' @param t A number
      #' @return Modifies the B matrix in place
      self$t <- t
      self$B <- as.data.frame( (self$B >= t)*1 )
      # Set the zeroed out species to -1
      self$B[self$B==0] <- -1
      invisible(self)
    },

    baseline.prep = function(){
      #' Count up the species saved by the baseline strategy, then remove it;
      #' These species are buffered and are added freely to nontrivial strategies at results time
      #' B is mutated by removing the baseline strategy, and the all_index is decremented
      #'
      #' @return Updates private$baseline.results 

      baseline.species.idx <- which(self$B[private$baseline.idx,] > 0)
      baseline.species.names <- colnames(self$B)[baseline.species.idx]
      species.names.string <- paste(baseline.species.names, sep=" | ")
      
      # Store in the species buffer 
      private$species.buffer <- c(private$species.buffer, baseline.species.names)

      if (length(baseline.species.idx > 0)) {
        # Remove baseline species from B, costs, and the all_index
        self$B <- self$B[-private$baseline.idx, -baseline.species.idx]
        self$cost.vector <- self$cost.vector[-private$baseline.idx]
        self$all.index <- self$all.index - 1
      }

      # Update baseline results
      baseline.num.species <- length(baseline.species.idx)
      baseline.cost <- 0
      baseline.threshold <- self$t 
      
      private$baseline.results <- list(numspecies = baseline.num.species,
                                       totalcost = baseline.cost,
                                       threshold = baseline.threshold,
                                       species.groups = species.names.string,
                                       strategies="Baseline",
                                       budget = baseline.cost)
      invisible(self)
    },
    
    parse.results = function(results){
      #' Convert the optimization results into something human readable
      #'
      #' @param results An OMPR solution object
      #' @return A list compiling the results of the optimization
      
      assignments <- get_solution(results, X[i,j])
      # Get entries of the assignment matrix 
      assignments <- assignments[assignments$value==1,]
      
      # Get strategy names
      strategy.idx <- sort(unique(assignments$i))
      strategy.names <- rownames(self$B)[strategy.idx]
      
      # Get strategy cost
      total.cost <- sum(self$cost.vector[strategy.idx])
      
      # Get species names
      species.idx <- sort(unique(assignments$j))
      species.names <- colnames(self$B)[species.idx]
      
      # Add in the baseline species
      species.names <- c(species.names, self$get.baseline.results()$species.groups)
      
      species.total <- length(species.names)
      threshold <- self$t
      
      # Return
      list(numspecies = species.total, 
           totalcost = total.cost,
           threshold = threshold,
           species.groups = species.names,
           strategies = strategy.names,
           assignments = assignments,
           budget = private$current.budget)
    },

    solve.ilp = function(budget){
      #' Solves the ILP given a budget
      #'
      #' @param budget A number
      #' @return A list of results
      private$current.budget <- budget
      B <- self$B
      strategy.cost <- self$cost.vector
      budget.max <- budget
      all_idx <- self$all.index

      # Number of strategies 
      n <- nrow(B)
      # Number of species
      m <- ncol(B)
      
      others <- which(1:n != all_idx) 
      
      # Set up the ILP
      # --------------
    
      model <- MIPModel() %>%
        
      # Decision variables 
      # ------------------
        
        # X[i,j] binary selection matrix 
        add_variable(X[i,j], i = 1:n, j = 1:m, type="binary") %>%
        # y[i] Strategy selection vector
        add_variable(y[i], i = 1:n, type="binary") %>%
        
        # Objective function
        # ------------------
        set_objective(sum_expr(B[i,j] * X[i,j], i = 1:n, j = 1:m)) %>%
        
        # Constraints
        # -----------
      
        # Constraint (1):
        # Ensure only one strategy applies to a target species
        add_constraint(sum_expr(X[i,j], i = 1:n) <= 1, j = 1:m) %>%
        
        # Constraint (2)
        # Force contributions of management strategy i to every target species j to be null if strategy i is not selected
        # forall(i in strategies, j in target) xij[i][j] <= yi[i];
        add_constraint(X[i,j] <= y[i], i = 1:n, j = 1:m) %>%
        
        # Constraint (3)
        # "All" strategy constraint - if the "all" strategy is active, all others must be deselected
        add_constraint(y[all_idx] + y[i] <= 1, i = others) %>%
        
        # Constraint (4)
        # Budget constraint
        add_constraint(sum_expr(y[i]*strategy.cost[i], i = 1:n) <= budget.max, i = 1:n)
      
      # Solve the model
      result <- solve_model(model, with_ROI(solver="lpsolve", verbose=FALSE))
      
      result
    }
  )
)

# ------------------------------
# Function to optimize over a range of thresholds
# ------------------------------

optimize.range <- function(B, cost.vector, all.index, budgets = NULL, thresholds = c(50.01, 60.01, 70.01), combo.strategies=NULL){
  #' Perform the optimization over a range of budgets and thresholds
  #'
  #' @param B A [strategies]x[species] dataframe with named rows and columns
  #' @param cost.vector A list of strategy costs
  #' @param all.index An integer signifying the index of the strategy that combines all strategies
  #' @param budgets A list of budgets over which to optimize. If NULL, a sensible range of budgets will be automatically generated
  #' @param thresholds A list of survival thresholds over which to optimize
  #' @param combo.strategies 
  

  # Set up the progress bar
  #progress.bar <- txtProgressBar(min=1, max=100, initial=1)
  #step <- 1

  # Collect results of the optimization here  
  out <- data.frame()
  debug.ctr <- 0
  for (threshold in thresholds) {
    
    # Initialize a new optimization run with an opStruct
    this.opt <- optStruct$new(B=B, cost.vector=cost.vector, all.index=all.index, t=threshold)
    
    # Check if combo information needs to be supplied
    if (!is.null(combo.strategies)){
      if (length(combo.strategies) > 2){
        stop("Error: Currently only one strategy is handled")
      }
      input <- combo.strategies[[1]]
      output <- combo.strategies[[2]]
      this.opt$add.combo(input, output)
    }
    
    if ( is.null(budgets) ){
      # No budget range supplied. Use the costs of individual strategies
      budgets <- make.budget(this.opt$cost.vector)  
    } 
    
    
    for (budget in budgets){
      # Run over the budgets and compile the results 
      
      optimization.result <- this.opt$solve(budget)
      
      out <- rbind(out, opt.result.to.df(optimization.result))
      
      # Update progress bar
      #step <- step + 1
      #setTxtProgressBar(progress.bar, step)
    }
  }
  print(paste("Ran", debug.ctr, "baselines"))
  out
}

opt.result.to.df <- function(opt.result){
  #' TODO: Documentation
  #' 
  #' @param opt.result A list
  #' @return slkdfl
  
  
  # Concatenate species groups
  species.groups.flat <- paste(opt.result$species.groups, collapse = " | ")
  # Concatenate strategies
  strategies.flat <- paste(opt.result$strategies, collapse = " + ")
  
  out <- data.frame(total_cost = opt.result$totalcost, 
                    strategies = strategies.flat, 
                    species_groups = species.groups.flat, 
                    threshold = opt.result$threshold,
                    number_of_species = opt.result$numspecies,
                    budget.max = opt.result$budget)
  out
}


make.budget <- function(cost.vector){
  #' Generate a list of budgets that adequately tests out different combinations of strategies
  #' Currently computes the prefix sum of the strategy cost vector and mixes it with the strategy costs
  #' 
  #' @param cost.vector A list of numbers
  #' @return A sorted list of new budget levels
  sorted.cost <- sort(cost.vector)
  csum <- cumsum(sorted.cost)
  out <- sort(c(csum, cost.vector))
  out <- out[out <= max(cost.vector)]
  out <- unique(out)
  return( c(0, out))
}

# ------------------------------
# Recreate the "correct results.png" plot (or try to)
# ------------------------------
Bij_fre_01 <- read.csv("~/Projects/Conservation/consOpt/testdata2/Bij_fre_01.csv")
cost_fre_01 <- read.csv("~/Projects/Conservation/consOpt/testdata2/cost_fre_01.csv")

# Prep benefits 
rownames(Bij_fre_01) <- Bij_fre_01$X
Bij_fre_01$X <- NULL

# Prep costs 
cost.vector <- cost_fre_01$Cost



# ------------------------------
# TESTING SHIT
# ------------------------------

# Initialize the optimization object for threshold=60.01
testOpt60 <- optStruct$new(B=Bij_fre_01,
                     cost.vector=cost.vector,
                     all.index=15,
                     t=60.01)


# Initialize the optimization object for threshold=50.01
testOpt50 <- optStruct$new(B=Bij_fre_01,
                           cost.vector=cost.vector,
                           all.index=15,
                           t=50.01)


# Get the S4+S5 strat
res50 <- testOpt50$solve(budget=5657184, debug=TRUE)

# Test adding combos
input <- list(strat1="S12", strat2="S13")
output <- list(strat1=c("S3", "S7", "S10"), strat2=c("S6", "S9", "S10"))
testOpt60$add.combo(input, output)

# Recover the S12+S13 strat
res60 <- testOpt60$solve(budget=204454450.5)

# Big range function
combo <- list(input, output)
test.range <- optimize.range(Bij_fre_01, cost.vector, all.index = 15, combo.strategies = combo)


# Ghetto results cleaning
test.range$duplicated <- duplicated(test.range$species_groups)
clean.results <- test.range[!test.range$duplicated,]
clean.results$duplicated <- NULL


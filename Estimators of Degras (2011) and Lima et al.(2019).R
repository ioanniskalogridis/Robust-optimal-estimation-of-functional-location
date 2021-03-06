require(KernSmooth)
require(fda)
require(CVXR)

Degr <- function(Y){
  # Y is the matrix of discretized functional predictors
  grid <- 1:dim(Y)[2]/dim(Y)[2]
  Ybar <- apply(Y, 2, FUN = mean)
  h = dpill(grid, Ybar)
  fit.loc <- locpoly(grid, Ybar, gridsize = dim(Y)[2], bandwidth = h)
  resids.X <- apply(Y, 1, FUN = function(x) mean((x-fit.loc$y)^2) )
  return(list(mu = fit.loc$y, h = h, resids = resids.X))
}

Cao <- function(Y, p = 4, k = 0.70){
  grid <- 1:dim(Y)[2]/dim(Y)[2]
  nbasis <- max(floor(0.3*dim(Y)[1]^{1/p}*log(n)),p)
  basis.b <- create.bspline.basis(rangeval = c(min(grid),max(grid))/max(grid), nbasis = nbasis, norder = p)
  basis.b.e <- eval.basis(grid/max(grid), basis.b)
  
  Pred.big <- basis.b.e
  Y.v = as.vector(t(Y))
  X.v = matrix(rep(t(Pred.big), dim(Y)[1]), ncol = ncol(Pred.big), byrow = TRUE)

  beta <- Variable(nbasis)
  obj <- sum(CVXR::huber(Y.v-X.v%*%beta, M = k))
  prob <- Problem(Minimize(obj))
  result <- solve(prob)

  mu = basis.b.e%*%result[[1]]
  return(list(mu = mu, nbasis = nbasis))
}

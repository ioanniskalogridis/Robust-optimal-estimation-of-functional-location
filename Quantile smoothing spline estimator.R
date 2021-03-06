require(fda)
require(SparseM)
require(MASS)

quan.smsp <- function(Y, tun = 1e-03, alpha = 0.5, r = 2, toler = 1e-06, max.it = 100, interval = NULL){
  
  rho.ch <- function(x, alpha = 0.5, tuning = 1e-03) {
    f <- ifelse(x <= tuning & x >=0, alpha*x^2/tuning, 
                ifelse(x >- tuning & x <= 0, (1-alpha)*x^2/tuning, x*(alpha-(x<0) ) ) ) 
    return(f)
  }
  psi.ch <-  function(x, alpha = 0.5, tuning = 1e-03) {
    f <- ifelse(x <= tuning & x >=0, 2*alpha*x/tuning, 
                ifelse(x >- tuning & x <= 0, 2*(1-alpha)*x/tuning, alpha*(x>0) + (alpha-1)*(x<0) ) ) 
    return(f)
  }
  weights.ch <- function(x, alpha = 0.5, tuning = 1e-03) {
    f <- ifelse(x <= tuning & x >=0, 2*alpha/tuning, 
                ifelse(x >- tuning & x <= 0, 2*(1-alpha)/tuning, alpha*(x>0)/x + (alpha-1)*(x<0)/x ) )
    return(f)
  }
  
  Y=Y[rowSums(is.na(Y)) !=ncol(Y), ]
  Y = as.matrix(Y)
  n <- dim(Y)[1]
  p <- dim(Y)[2]
  grid <- 1:p/p
  b.basis <- create.bspline.basis(rangeval = c(grid[1], grid[p]), breaks = grid, norder = 2*r)
  b.basis.e <- eval.basis(b.basis, grid)
  T.m <- t(apply(Y, 1, FUN = function(x) x <- 1:dim(Y)[2] ))
  T.m[is.na(Y)] <- NA
  B <- matrix(0, nrow = (p+2*r-2), ncol = (n*p)-sum(is.na(T.m))  )
  # B2 <- matrix(0, nrow = (p+2), ncol = (n*p)-sum(is.na(T.m))  )
  
  for(j in 1:((n*p)-sum(is.na(T.m)))){
    B[, j] <- b.basis.e[ na.omit(as.vector(t(T.m)))[j], ]
  }
  ms <- as.vector(apply(T.m, 1, FUN = function(x) p-sum(is.na(x))))
  h.m <- 1/mean(1/ms)
  ms <- rep(ms, times = c(ms))
  B.s <- scale(B, center = FALSE, scale =  ms)
  B.p <- B.s%*%t(B)
  
  # Penalty matrix, see, e.g., de Boor (2001)
  grid.a <- c(0, grid)
  if(r==1){
    Pen.matrix =  (diag(1/ (diff(grid.a)))%*%diff(diag(length(grid.a)), differences = 1) )%*%t(diag(1/ (diff(grid.a)))%*%diff(diag(length(grid.a)), differences = 1) )
  } else{
    Pen.matrix =  bsplinepen(b.basis, Lfdobj= r)
  }
  
  par.in = 100*(h.m*n)^{-2*r/(2*r+1)}
  fit.in.c <- ginv(B.p+par.in*Pen.matrix)%*%(B.s%*%na.omit(as.vector(as.matrix(t(Y)))))
  resids.ls <- na.omit(as.vector(t(Y)))-t(B)%*%fit.in.c
  
  quan.irls <- function(X, X.s, y, tau, tuning, tol = toler, pen, 
                        P, resids.in, maxit){
    
    ic = 0
    istop = 0
    
    while(istop == 0 & ic <= maxit){
      ic = ic + 1
      weights.prelim <- as.vector(weights.ch(resids.in,  tau, tuning))
      M1 <-  t(t(X.s)*weights.prelim)%*%t(X) + 2*pen*P
      M2 <-  t(t(X.s)*weights.prelim)%*%na.omit(as.vector(as.matrix(t(y))))
      v1 = SparseM::solve(M1, M2)
      resids1 <- as.vector(na.omit(as.vector(t(y)))-t(X)%*%v1)
      check = max( abs(resids1-resids.in) ) 
      if(check < tol){istop =1}
      resids.in <- resids1
    }
    weights1 = as.vector(weights.ch(resids1, tau, tuning) )
    hat.tr <- sum( diag(SparseM::solve(M1,  t(t(X.s)*weights1))%*%t(X)))/length(na.omit(as.vector(as.matrix(t(y)))))
    # hat.tr <- mean( diag(t(X)%*%SparseM::solve(M1,  t(t(X.s)*weights1))) ) 
    return(list(resids = resids1, beta.hat = v1, hat.tr = hat.tr, ic = ic,
                weights = weights1 ) ) 
  }
  GCV <- function(lambda){
    fit.r <- quan.irls(X = B, X.s = B.s, y = Y, resids.in = resids.ls, maxit = max.it,
                       pen = lambda, P = Pen.matrix, tau = alpha, tuning = tun)
    GCV.scores <- mean( fit.r$weights*1/ms*(fit.r$resids)^2/((1-fit.r$hat.tr)^2)  )
    return(GCV.scores)
  }
  if(is.null(interval)){
    lambda.cand <- c(1e-09, 1e-08, 3e-08, 6e-08, 9e-08, 1e-07, 3e-07, 6e-07, 9e-07, 1e-06, 3e-06, 6e-06, 9e-06, 
                     1e-05, 3e-05, 6e-05, 9e-05, 1e-04, 3e-04, 6e-04, 9e-04,  1e-03, 4e-03, 7e-03,
                     1e-02, 4e-02, 7e-02, 1e-01, 6e-01, 2)
    lambda.e <- sapply(lambda.cand, FUN  = GCV)
    wm <- which.min(lambda.e)
    if(wm == 1){wm <- 2}
    if(wm == length(lambda.cand)){wm <- (length(lambda.cand)-1)  }
    lambda1 <- optimize(f = GCV, lower = lambda.cand[wm-1], upper = lambda.cand[wm+1])$minimum
  } else {
    lambda1 <- optimize(f = GCV, interval = interval)$minimum}
  
  
  fit.f <- quan.irls(X = B, X.s = B.s, y=  Y, resids.in = resids.ls, maxit = max.it,
                     pen = lambda1, P = Pen.matrix, tau = alpha, tuning = tun)
  mu = b.basis.e%*%fit.f$beta.hat
  return(list(mu = mu, weights = fit.f$weights, Pen.matrix = Pen.matrix,
              lambda = lambda1))
}

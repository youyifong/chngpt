# threshold.type
# segmented2 differs from segmented in parameterization, it is the model studied in Cheng 2008
# M20 and M02 differ from upperhinge and hinge in that they have a quadratic term
expit.2pl=function(x,e,b) sapply(x, function(x) 1/(1+exp(-b*(x-e))))
sim.chngpt = function (
    mean.model=c("thresholded","thresholdedItxn","quadratic","quadratic2b","cubic2b","exp","flatHyperbolic","z2","z2hinge","z2segmented","z2linear","logistic"), 
    threshold.type=c("NA",
          "M01","M02","M03", # hinge models
          "M10","M20","M30",# upper hinge models
          "M11","M21","M12","M22","M22c","M31","M13","M33c", # segmented models with higher order trends
          "hinge","segmented","upperhinge","segmented2","step","stegmented"), # segmented2 is the model studied in Cheng (2008)
    b.transition=Inf,
    family=c("binomial","gaussian"), 
    x.distr=c("norm","norm3","norm6","imb","lin","mix","gam","zbinary","gam1","gam2", "fixnorm","unif"), # gam1 is a hack to allow e. be different
    e.=NULL, mu.x=4.7, sd.x=NULL, sd=0.3, mu.z=0, 
    alpha=NULL, alpha.candidate=NULL, coef.z=log(1.4), beta=NULL, beta.itxn=NULL, 
    logistic.slope=15,
    n, seed, 
    weighted=FALSE, # sampling weights
    heteroscedastic=FALSE,
    ar=FALSE,
    verbose=FALSE) 
{
    
    if (!requireNamespace("mvtnorm")) {print("mvtnorm does not load successfully"); return (NULL) }
    if (!is.numeric(n)) stop("n is not numeric")
    
    if (missing(threshold.type) & startsWith(mean.model,"thresholded")) stop("threshold.type mssing")
    if (missing(family)) stop("family mssing")
    threshold.type<-match.arg(threshold.type)    
    if (threshold.type=="M01") threshold.type="hinge"
    if (threshold.type=="M10") threshold.type="upperhinge"
    if (threshold.type=="M11") threshold.type="segmented"
    
    
    mean.model<-match.arg(mean.model)    
    family<-match.arg(family)    
    x.distr<-match.arg(x.distr)    
    
    if(is.null(sd.x)) sd.x=if (mean.model=="quadratic") sd.x=1.4 else 1.6
    
    set.seed(seed)
    
    #######################################################################################
    # generate covariates
    
    if(x.distr=="imb") { # imbalance
        x=c(rnorm(n-round(n/3), mu.x, sd.x), mu.x-abs(rnorm(round(n/3), 0, sd.x)))
        z=rep(1,n)
    } else if(x.distr=="unif") { # unif
        x=runif(n)*4*sd.x + mu.x-2*sd.x # under quadratic, 4*1.4  +  4.7-2*1.4
        z=rnorm(n, mean=mu.z, 1)
    } else if(x.distr=="lin") { # linearly evenly spaced
        x=seq(0,1,length=n)*4*sd.x + mu.x-2*sd.x
        z=rnorm(n, mean=mu.z, 1)
    } else if(x.distr=="mix") { # mixture
        x=c(rnorm(n*.6, mu.x, sd.x), rep(mu.x-2*sd.x, n*.4))
        z=rep(1,n)
    } else if(x.distr %in% c("gam","gam1","gam2")) { # gamma
        x=1.4*scale(rgamma(n=n, 2.5, 1))+mu.x/2
        z=rnorm(n, mean=mu.z, 1)
        if(x.distr=="gam") e.=2.2 else if(x.distr=="gam1") e.=1.5 else if(x.distr=="gam2") e.=1 
        # for thresholded, override input
        if (mean.model=="thresholded") {
            if(x.distr=="gam") {
                alpha= if (threshold.type=="hinge") -0.5 else if(threshold.type=="segmented") -1.3 else stop("wrong threshold.type") # to have similar number of cases
            } else if (x.distr=="gam1") {
                alpha= if (threshold.type=="hinge") -0.2 else if(threshold.type=="segmented") -1 else stop("wrong threshold.type") # to have similar number of cases
            } else if (x.distr=="gam2") {
                alpha= if (threshold.type=="hinge") 0.2 else if(threshold.type=="segmented") -0.6 else stop("wrong threshold.type") # to have similar number of cases
            }            
        }            
        x.distr="gam" # the number trailing gam is only used to change e.
        
    } else if(startsWith(x.distr,"norm")) { 
        if (x.distr=="norm") {
             rho=0
        } else if (x.distr=="norm3") {
            rho=0.3 
        } else if (x.distr=="norm6") {
            rho=0.6
        } else {
            stop("x.distr not supported: "%.%x.distr)
        }        
        tmp=mvtnorm::rmvnorm(n, mean = c(mu.x,mu.z), sigma = matrix(c(sd.x^2,sd.x*rho,sd.x*rho,1),2)) # use mvtnorm
        x=tmp[,1]
        z=tmp[,2]    
        
    } else if(x.distr=="fixnorm") { 
    # z is not random, x is
        set.seed(999999) # this is chosen to minize the probability that it equals seed, which would create a problem
        z=rnorm(n, mean = mu.z, sd = 1)    
        set.seed(seed)
        x=rnorm(n, mean = mu.x, sd = sd.x)
        
    } else if(startsWith(x.distr,"zbinary")) { 
        x=rnorm(n, mu.x, sd.x)
        z=rbern(n, 1/2)-0.5
        
    } else stop("x.distr not supported: "%.%x.distr)    
    
    if (is.null(e.) | !startsWith(mean.model,"thresholded")) e.=4.7 # hard code e. for mean models other than thresholded
    if (verbose) {print(e.); print(mean(x<e.))}
    
    
    x.gt.e = expit.2pl(x, e=e., b=b.transition)  # 1 if x>e., 0 if x<e.
    x.gt.e[is.nan(x.gt.e)]=0# otherwise we would get NA in the simulated data
    x.lt.e = 1-x.gt.e # 1 if x>e., 0 if x<e.
#    # test. note that when x==e., returns NaN
#    expit.2pl(c(.9,1,1.1), e=1, b=Inf)
    
    
        
    #######################################################################################
    # make design matrix and coefficients
    
    if (startsWith(mean.model,"thresholded")) {        
        
        # when mean.model is not found, alpha remains a null, and do not throw an error
        # but if mean.model is NULL, an error is thrown
        if(!is.null(alpha.candidate)) alpha=alpha.candidate # used to determine sim.alphas
        #cat(e., beta, "\n")
        if(is.null(alpha)) alpha=try(chngpt::sim.alphas[[mean.model%.%"_"%.%sub("fix","",x.distr)]][e.%.%"", ifelse(mean.model=="thresholdedItxn",beta.itxn,beta)%.%""], silent=TRUE)
        if(is.null(alpha) | inherits(alpha, "try-error")) stop("alpha not found, please check beta or provide a null") 
        
        X=cbind(1,     z,        x,   x.gt.e,   if(threshold.type=="segmented2") x.gt.e*x else x.gt.e*(x-e.),     z*x,   z*x.gt.e,   z*x.gt.e*(x-e.), x.lt.e*(x-e.), (x.lt.e*(x-e.))^2, (x.gt.e*(x-e.))^2, (x.lt.e*(x-e.))^3, (x.gt.e*(x-e.))^3)
        coef.=c(intercept=alpha, z=coef.z, x=0, x.gt.e=0, x.hinge=0,                                              z.x=0, z.x.gt.e=0, z.x.hinge=0,     x.uhinge=0,     x.uhinge.quad=0,   x.hinge.quad=0,     x.uhinge.cubic=0,   x.hinge.cubic=0)
        if (mean.model=="thresholded") { 
            if (threshold.type=="step") {
                coef.[1:5]=c(alpha, coef.z,          0,    beta,     0) 
            } else if (threshold.type=="hinge") {
                coef.[1:5]=c(alpha, coef.z,          0,       0,  beta) 
            } else if (threshold.type=="M02") {
                coef.[1:5]=c(alpha, coef.z,          0,       0,     0); coef.["x.hinge"]=beta[1];  coef.["x.hinge.quad"]=beta[2]
            } else if (threshold.type=="M03") {
                coef.[1:5]=c(alpha, coef.z,          0,       0,     0); coef.["x.hinge"]=beta[1];  coef.["x.hinge.quad"]=beta[2];  coef.["x.hinge.cubic"]=beta[3]
            } else if (threshold.type=="upperhinge") {
                coef.[1:5]=c(alpha, coef.z,          0,       0,     0); coef.["x.uhinge"]=beta 
            } else if (threshold.type=="M20") {
                coef.[1:5]=c(alpha, coef.z,          0,       0,     0); coef.["x.uhinge"]=beta[1]; coef.["x.uhinge.quad"]=beta[2]
            } else if (threshold.type=="M30") {
                coef.[1:5]=c(alpha, coef.z,          0,       0,     0); coef.["x.uhinge"]=beta[1]; coef.["x.uhinge.quad"]=beta[2]; coef.["x.uhinge.cubic"]=beta[3]
            } else if (threshold.type=="segmented") {
                if(length(beta)==1) coef.[1:5]=c(alpha, coef.z,  -log(.67),       0,  beta) else {
                coef.[1:5]=c(alpha, coef.z,          0,       0,     0); coef.["x"]=beta[1]; coef.["x.hinge"]=beta[2]
                }
            } else if (threshold.type=="segmented2") {
                coef.[1:5]=c(alpha, coef.z,  -log(.67),       0,  beta) 
            } else if (threshold.type=="M12") {
                coef.[1:5]=c(alpha, coef.z,  0,       0,  0); coef.["x.uhinge"]=beta[1]; coef.["x.hinge"]=beta[2]; coef.["x.hinge.quad"]=beta[3]; 
            } else if (threshold.type=="M21") {
                coef.[1:5]=c(alpha, coef.z,  0,       0,  0); coef.["x.uhinge"]=beta[1]; coef.["x.uhinge.quad"]=beta[2]; coef.["x.hinge"]=beta[3];
            } else if (threshold.type=="M22") {
                coef.[1:5]=c(alpha, coef.z,  0,       0,  0); coef.["x.uhinge"]=beta[1]; coef.["x.uhinge.quad"]=beta[2]; coef.["x.hinge"]=beta[3]; coef.["x.hinge.quad"]=beta[4]; 
            } else if (threshold.type=="M22c") {
                coef.[1:5]=c(alpha, coef.z,  0,       0,  0); coef.["x.uhinge"]=beta[1]; coef.["x.uhinge.quad"]=beta[2]; coef.["x.hinge"]=beta[1]; coef.["x.hinge.quad"]=beta[3]; 
    
            } else if (threshold.type=="M31") {
                coef.[1:5]=c(alpha, coef.z,  0,       0,  0); coef.["x.uhinge"]=beta[1]; coef.["x.uhinge.quad"]=beta[2]; coef.["x.uhinge.cubic"]=beta[3]; coef.["x.hinge"]=beta[4];
            } else if (threshold.type=="M13") {
                coef.[1:5]=c(alpha, coef.z,  0,       0,  0); coef.["x.hinge"]=beta[1]; coef.["x.hinge.quad"]=beta[2]; coef.["x.hinge.cubic"]=beta[3]; coef.["x.uhinge"]=beta[4];
            } else if (threshold.type=="M33c") {
                coef.[1:5]=c(alpha, coef.z,  0,       0,  0); coef.["x.uhinge"]=beta[1]; coef.["x.hinge"]=beta[1]; coef.["x.uhinge.quad"]=beta[2]; coef.["x.hinge.quad"]=beta[2]; coef.["x.uhinge.cubic"]=beta[3]; coef.["x.hinge.cubic"]=beta[4]; 
    
            } else if (threshold.type=="stegmented") {
                coef.[1:5]=c(2,     coef.z,   log(.67), log(.67), beta) # all effects of x in the same direction, subject to perfect separation, though that does not seem to be the main problem
                #coef.[1:5]=c(0, coef.z, -log(.67), log(.67), beta) # effects of x and x.gt.e in different direction
            }            
            
        } else if (mean.model == "thresholdedItxn") { 
        # intercept + main effect + interaction
        # used to be "sigmoid3","sigmoid4","sigmoid5"
    #        beta.var.name=switch(threshold.type,step="x.gt.e",hinge="x.hinge",segmented="x.hinge",stegmented="x.hinge")
    #        coef.[beta.var.name]=switch(mean.model,sigmoid3=log(.67),sigmoid4=-log(.67),sigmoid5=0)
    #        coef.["z."%.%beta.var.name]=beta
    #        if (threshold.type=="segmented") {coef.["x"]=tmp; coef.["z.x"]=log(.67) } 
            beta.var.name=switch(threshold.type,step="x.gt.e",hinge="x.hinge",segmented="x.hinge",stegmented="x.hinge")
            coef.[beta.var.name]=beta
            coef.["z."%.%beta.var.name]=beta.itxn
            if (threshold.type=="segmented") {coef.["x"]=tmp; coef.["z.x"]=log(.67) }    
        }
    #    else if (mean.model=="sigmoid1") { 
    #    # intercept only
    #        coef.["x.gt.e"]=beta
    #        coef.["z"]=0
    #    } else if (mean.model=="sigmoid6") { 
    #    # special treatment, model misspecification
    #        coef.=c(alpha, coef.z, log(.67),  beta)
    #        X=cbind(1, z, x.gt.e, x.gt.e*z^3)    
        
        
    } else if (mean.model=="logistic") { 
    # from Banerjee and McKeague
        X=cbind(1,     z,        expit(logistic.slope*(x-.5)))
        coef.=c(alpha=0, z=coef.z, x=1)
    
    } else if (mean.model=="quadratic") { 
    # x+x^2 
        X=cbind(1,     z,        x,   x*x)
        coef.=c(alpha=-1, z=coef.z, x=-1 , x.quad=0.3)
    
    } else if (mean.model=="quadratic2b") { 
        X=cbind(1,     z,        x,   x*x)
        coef.=c(alpha=-1, z=coef.z, x=-2*mu.x , x.quad=1)
    
    } else if (mean.model=="cubic2b") { 
    # x+x^2+x^3
        X=cbind(1,     z,        x,   x*x,   x*x*x)
        coef.=c(alpha=-1, z=coef.z, x=-1 , x.quad=beta, x.cubic=1)
    
    } else if (mean.model=="exp") { 
        if(x.distr=="norm") {
            X=cbind(1,     z,        exp((x-5)/2.5))
            coef.=c(alpha=-5, z=coef.z, expx=4)
        } else if(x.distr=="gam") {
            X=cbind(1,     z,        exp((x-5)/2.5))
            coef.=c(alpha=-3, z=coef.z, expx=4)
        } else stop("wrong x.distr")
    
    } else if (mean.model=="flatHyperbolic") { 
    # beta*(x-e)+beta*sqrt((x-e)^2+g^2)
        if(x.distr=="norm") {
            g=1
            X=cbind(1,     z,        (x-e.)+sqrt((x-e.)^2+g^2) )
            coef.=c(alpha=-5, z=coef.z, 2)
        } else if(x.distr=="gam") {
            g=1
            X=cbind(1,     z,        (x-4)+sqrt((x-4)^2+g^2) )
            coef.=c(alpha=-2, z=coef.z, 2)
        }
    
    } else if (mean.model=="z2") { 
    # z^2
        X=cbind(1,     z,        z*z)
        coef.=c(alpha=alpha, z=coef.z, z.quad=0.3)    
    } else if (mean.model=="z2hinge") { 
    # z^2 + (x-e)+
        X=cbind(1,     z,        z*z,     x.gt.e*(x-e.))
        coef.=c(alpha=alpha, z=coef.z, z.quad=0.3, beta)
    } else if (mean.model=="z2linear") { 
    # z^2 + x
        X=cbind(1,     z,        z*z,     x)
        coef.=c(alpha=alpha, z=coef.z, z.quad=0.3, -log(.67))    
    } else if (mean.model=="z2segmented") { 
    # z^2 + x + (x-e)+
        X=cbind(1,     z,        z*z,     x,    x.gt.e*(x-e.))
        coef.=c(alpha=alpha, z=coef.z, z.quad=0.3, -log(.67), beta)
    
    } else stop("mean.model not supported: "%.%mean.model)     
    if (verbose) myprint(coef., digits=10)
    
    linear.predictors=drop(X %*% coef.)
    
    # simulate y
    y=if(family=="binomial") {
        rbern(n, expit(linear.predictors)) 
    } else if(family=="gaussian") {
        linear.predictors +
            if (!heteroscedastic & !ar) {
                rnorm(n, 0, sd)
            } else if (heteroscedastic & !ar) {
                if (heteroscedastic==1) {
                    rnorm(n, 0, sd*abs(linear.predictors))
                } else if (heteroscedastic==2) {
                    rnorm(n, 0, sd/2+sd/2*sqrt(abs(linear.predictors)))            
                } else stop("wrong value for heteroscedastic")        
            } else if (!heteroscedastic & ar){
                rnorm.ar(n, sd, rho=ar)
            } else {
                rnorm.ar(n, sd, rho=ar) * (sd/2+sd/2*sqrt(abs(linear.predictors)))
            }
    }
    
    dat=data.frame (
        y=y,
        z=z,         
        
        x=x,
        x.sq=x*x,
        x.gt.e=x.gt.e,
        x.hinge=x.gt.e*(x-e.),
        x.bin.med=ifelse(x>median(x), 1, 0),
        x.tri = factor(ifelse(x>quantile(x,2/3),"High",ifelse(x>quantile(x,1/3),"Medium","Low")), levels=c("Low","Medium","High")),
        
        x.tr.1=ifelse(x>log(100), x, 0) ,
        x.tr.2=ifelse(x>log(100), x, log(100)) ,
        x.tr.3=ifelse(x>3.5, x, 0) ,
        x.tr.4=ifelse(x>3.5, x, 3.5), 
        x.tr.5=ifelse(x>3.5, x, 3.5/2), 
        x.tr.6=ifelse(x>5, x, 5) ,
        x.ind =ifelse(x>3.5, 0, 1), 
        
        x.bin.35=ifelse(x>3.5, 1, 0), 
        x.bin.6=ifelse(x>6, 1, 0) ,
        x.bin.log100=ifelse(x>log(100), 1, 0),
        
        eta=linear.predictors
    )        
    
    # sampling
    if(weighted) {
        if (family=="gaussian") {
            # create strata
            dat$strata=ifelse(dat$y>4, 1, 2)
            #table(dat$strata)
            dat$sampling.p=ifelse(dat$strata %in% c(1), 1, 0.5)
            dat=dat[rbern(n, dat$sampling.p)==1,]
            
        } else if (family=="binomial") {
            # create strata
            dat$strata=2-dat$y # 1: cases; 2: controls
            dat$strata[dat$strata==2 & dat$z>0]=3
            #table(dat$strata)
            dat$sampling.p[dat$strata==1]=1
            dat$sampling.p[dat$strata==2]=1
            dat$sampling.p[dat$strata==3]=0.5
            dat=dat[rbern(n, dat$sampling.p)==1,]
            
        } else stop("weighted not supported here yet")
    } else {
        dat$sampling.p=rep(1, nrow(dat))
    }
    
    names(coef.) = name.conversion.2(names(coef.))
    
    attr(dat, "coef")=coef.
    attr(dat, "chngpt")=e.
    dat
}


sim.twophase.ran.inte=function(threshold.type, n, seed) {
    tmp = sim.chngpt(mean.model="thresholded", threshold.type=threshold.type, n=n, seed=seed, beta=c(2,2), x.distr="lin", e.=5, family="gaussian", alpha=0, sd=3, coef.z=1)    
    g=16 # number of clusters
    w=rnorm(g,sd=10)
    w=c(rep(w, each=floor(n/g)), rep(last(w), n-g*floor(n/g)))
    id=c(rep(1:g, each=floor(n/g)), rep(g, n-g*floor(n/g)))
    scramble=sample(n)
    dat = cbind(tmp, w=w[scramble], id=id[scramble])
    dat$y=dat$y+dat$w    
    attr(dat,"coef")=attr(tmp,"coef")
    attr(dat,"chngpt")=attr(tmp,"chngpt")
    dat
}


# three phase data
sim.threephase = function(n, seed, gamma = 1, e = 3, beta_e = 5, f = 7, beta_f = 2, coef.z=1){
  ## This function generates data using a simple data generating mechanism for validation purposes.
  ## The default true model is Y = Z + 5*(X - 3)_ + 2*(X - 7)_ + 1*X + epsilon
  set.seed(seed)
  x <- runif(n = n, min = -1, max = 10)
  z <- runif(n = n, min =  -4, max = 4) 
  y <- 0
  dat = data.frame(y,z,x)
    
  dat[x<e,]$y = beta_e*(dat[x<e,]$x - e) + beta_f*(dat[x<e,]$x - f) + gamma*(dat[x<e,]$x)
  dat[x>=e & x<f,]$y = 0*(dat[x>=e & x<f,]$x - e) + beta_f*(dat[x>=e & x<f,]$x - f) + gamma*(dat[x>=e & x<f,]$x)
  dat[x>=f,]$y = 0*(dat[x>=f,]$x - e) + 0*(dat[x>=f,]$x - f) + gamma*(dat[x>=f,]$x)
  # for simplicity, here we assume epsilon is zero
  dat$y = dat$y + coef.z*z # + rnorm(n = n)
  
  return(dat)
}

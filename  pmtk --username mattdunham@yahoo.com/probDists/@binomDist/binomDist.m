classdef binomDist < discreteDist
  
  properties
    N; 
    mu;
  end
  
  properties(GetAccess = 'private')
    lockN;
  end
  
  %% Main methods
  methods 
    function obj =  binomDist(N,mu)
      % binomdist(N,mu) binomial distribution
      % N and/or mu can be vectors.
      % If both are vectors, must be same length.
      % If one is a scalar, it is replicated.
      % N is mandatory; mu can be omitted or set to [] if it will be
      % estimated (using fit).
      % mu can also be a random variable
      % eg pr = binomdist(10, betadist(1,1))
      obj; % make dummy object
      if nargin == 0;
        N = []; mu = [];
      end
      obj = setup(obj, N, mu);
      obj.support = 0:N;
    end
    
    
    function obj = set.N(obj, N)
      if obj.lockN
        % for bernoulli case
        %obj.N = 1;
        warning('BLT:binomdist:setN', 'can''t change N');
      else
        obj.N = N;
      end
    end


    function d = nfeatures(obj)
      d = length(obj.N);
    end

    
    function m = mean(obj)
     checkParamsAreConst(obj)
      m = obj.N .* obj.mu;
    end
    
    function m = mode(obj)
      checkParamsAreConst(obj)
      m = floor( (obj.N)+1 .* obj.mu );
    end  
    
    function m = var(obj)
      checkParamsAreConst(obj)
       m = obj.N .* obj.mu .* (1-obj.mu);
    end
 
   
    function X = sample(obj, n)
       % X(i,j) = sample from params(j) for i=1:n
       checkParamsAreConst(obj)
       d = nfeatures(obj);
       X = zeros(n, d);
       % Binomial is a sum of N bernoulli rv's
       for j=1:d
         X(:,j) = sum( rand(n,obj.N(j)) < repmat(obj.mu(j), n, obj.N(j)), 2);
         %X(:,j) = binornd(obj.N(j), obj.mu(j), n, 1);
       end
     end
    
     function p = logprob(obj, X, paramNdx)
       % p(i,j) = log p(x(i) | params(j))
       % eg., logprob(binomdist(10,[0.5 0.1]), 1:10)
       checkParamsAreConst(obj)
       d = nfeatures(obj);
       if nargin < 3, paramNdx = 1:d; end
       x = X(:);
       n = length(x);
       p = zeros(n,length(paramNdx));
       for jj=1:length(paramNdx)
         j = paramNdx(jj);
         if useStatsToolbox
           p(:,jj) = log(binopdf(x, obj.N(j), obj.mu(j)));
         else
           % LOG1P  Compute log(1+z) accurately.
           p(:,jj) = nchoosekln(obj.N(j), x) + ...
             x.*log(obj.mu(j)) + (obj.N(j) - x).*log1p(-obj.mu(j));
         end
       end
     end


     function logZ = lognormconst(obj)
       logZ = 0;
     end
     
     function obj = fit(obj, varargin)
       % m = fit(model, 'name1', val1, 'name2', val2, ...)
       % Arguments are
       % data - data(j) = number of successes (out of Ntrials) in experiment j
       % suffStat - [totalNumSucc totalNumTrials]
       % method - one of  'map' or 'mle'
       [X, suffStat, method] = process_options(...
         varargin, 'data', [], 'suffStat', [], 'method', 'mle');
       if ~isempty(suffStat)
         Nsucc = suffStat(1); Ntot = suffStat(2);
       else
         Nsucc = sum(X); Ntot = length(X) * obj.N;
       end
       Nfail = Ntot - Nsucc;
       switch method
         case 'mle'
           obj.mu =  Nsucc/Ntot;
         case 'map'
           switch class(obj.mu)
             case 'betaDist'
               obj.mu = (obj.mu.a + Nsucc - 1) / (obj.mu.a + Nsucc + obj.mu.b + Nfail - 2);
             otherwise
               error(['cannot handle mu of type ' class(obj.mu)])
           end
       end
     end

      function obj = inferParams(obj, varargin)
       % m = inferParams(model, 'name1', val1, 'name2', val2, ...)
       % Arguments are
       % data - data(j) = number of successes (out of Ntrials) in experiment j
       % suffStat - [totalNumSucc totalNumTrials]
       [X, suffStat] = process_options(...
         varargin, 'data', [], 'suffStat', []);
       if ~isempty(suffStat)
         Nsucc = suffStat(1); Ntot = suffStat(2);
       else
         Nsucc = sum(X); Ntot = length(X) * obj.N;
       end
       Nfail = Ntot - Nsucc;
       switch class(obj.mu)
         case 'betaDist'
           obj.mu = betaDist(obj.mu.a + Nsucc, obj.mu.b + Nfail);
         case 'discreteDist',
           Thetas = obj.mu.support;
           lik = Thetas.^Nsucc .* (1-Thetas).^Nfail;
           prior = obj.mu.probs;
           post = normalize(prior .* lik);
           obj.mu = discreteDist(post, Thetas);
         otherwise
           error(['cannot handle mu of type ' class(obj.mu)])
       end
      end

     
     function pr = predict(obj)
       % p(X|muHat)
      pr = obj;
     end
     
     function pr = postPredict(obj)
       % p(X|D) 
       switch class(obj.mu)
         case 'betaDist' % integrrate out mu
           pr = betaBinomDist(obj.N, obj.mu.a, obj.mu.b);
         otherwise
           error(['unrecognized mu type ' class(obj.mu)])
       end
     end

  end

  %% demos 
  methods(Static = true)
    function demoPlot()
       thetas = [1/2 1/4 3/4 0.9];
       N = 10;
       figure;
       for i=1:4
         subplot(2,2,i)
         plot(binomDist(N, thetas(i)));
         title(sprintf('theta=%5.3f', thetas(i)))
       end
    end

    function demoPost()
      binomDist.helperPost(2,2,3,17);
      binomDist.helperPost(5,2,11,13);
    end
     
          
    function helperPost(a, b, N1, N0)
      N = N1+N0;
      m = binomDist(N, betaDist(a,b));
      %m = bernoulliDist(betaDist(a,b));
      prior = m.mu; % betaDist
      m = inferParams(m, 'suffStat', [N1 N]);
      post = m.mu; % betaDist
      % The likelihood is the prior with a flat prior
      m2 = binomDist(N, betaDist(1,1));
      m2 = inferParams(m2, 'suffStat', [N1 N]);
      lik = m2.mu; % betaDist
      figure;
      h = plot(prior, 'plotArgs', {'r-', 'linewidth', 3});
      legendstr{1} = sprintf('prior Be(%2.1f, %2.1f)', prior.a, prior.b);
      hold on
      h = plot(lik, 'plotArgs', {'k:', 'linewidth', 3});
      legendstr{2} = sprintf('lik Be(%2.1f, %2.1f)', lik.a, lik.b);
      h = plot(post, 'plotArgs', {'b-.', 'linewidth', 3});
      legendstr{3} = sprintf('post Be(%2.1f, %2.1f)', post.a, post.b);
      legend(legendstr)
    end

   
  
    function demoPostPred
      N = 10;
      X = [1 2];
      N1 = sum(X);
      N0 = N*length(X)-N1;
      [N1 N0]
      a = 2;
      b = 2;
      m = binomDist(N, betaDist(a,b));
      %m = bernoulliDist(betaDist(a,b));
      prior = m.mu; % betaDist
      m0 = postPredict(m); figure; plot(m0); title('prior predictive')
      m = inferParams(m, 'data', X);
      mm = postPredict(m); % posterior predictive is betaBinomDist
      figure;
      h1 = plot(mm, 'plotArgs', 'b'); title('posterior predictive')
      % MAP estimation
      m3 = binomDist(N, betaDist(a,b));
      m3 = fit(m3, 'data', X, 'method', 'map');
      %m3.mu % constant vector
      mm3 = predict(m3); % binomDist
      hold on
      h3 = plot(mm3);
      set(h3, 'faceColor','r','barwidth',0.5);
      legend('postpred', 'plugin');
    end
end
  
  %% Private methods
  methods(Access = 'protected')
    % we make the constructor and set method call these functions
    % which can be overwitten by bernoullidist (child class)

    function obj = setup(obj,N,mu, lockN)
      % binomdist(N,mu) binomial distribution
      % N and/or mu can be vectors.
      % If both are vectors, must be same length.
      % If one is a scalar, it is replicated.
      % N is mandatory; mu can be omitted or set to [] if it will be
      % estimated (using fit).
      % mu can also be a random variable
      % eg pr = binomdist(10, betadist(1,1))
      if nargin < 4, lockN = false; end
      if isa(mu, 'double')
        d = max(length(N), length(mu));
        if isscalar(N), N = N*ones(1,d); end
        if isscalar(mu), mu = mu*ones(1,d); else mu = mu(:)'; end
      end
      obj.lockN = false;
      obj.N = N; % always possible since unlocked
      obj.mu = mu;
      %obj.names = {'X', 'mu'};
      obj.lockN = lockN;
    end


    function checkParamsAreConst(obj)
      p = isa(obj.mu, 'double');
      if ~p
        error('parameters must be constants')
      end
    end

  end
  
end
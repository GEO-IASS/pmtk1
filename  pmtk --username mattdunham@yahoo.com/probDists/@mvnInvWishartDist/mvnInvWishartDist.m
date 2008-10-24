classdef mvnInvWishartDist < vecDist
  % p(m,S|params) = N(m|mu, 1/k * S) IW(S| dof, Sigma)
  properties
    mu;
    Sigma;
    dof;
    k;
  end

  %% main methods
  methods
    function m = mvnInvWishartDist(varargin)
      if nargin == 0, varargin = {}; end
      [mu, Sigma, dof, k] = process_options(...
        varargin, 'mu', 0, 'Sigma', 1, 'dof', 1, 'k', []);
      d = length(mu);
      if isempty(k), k = d; end
      m.mu = mu; m.Sigma = Sigma; m.dof = dof; m.k = k;
    end
    
    function d = ndims(obj)
      % for the purposes of plotting etc, the dimensionality is |m|+|S|
      d = length(obj.mu) + length(obj.Sigma(:));
    end
    
    function lnZ = lognormconst(obj)
      d = length(obj.mu); 
      v = obj.dof;
      S = obj.Sigma;
      k = obj.k;
      lnZ = (v*d/2)*log(2) + mvtGammaln(d,v/2) -(v/2)*logdet(S) + (d/2)*log(2*pi/k);
    end
    
    function xrange = plotRange(obj)
      d = length(obj.mu);
      if d > 1, error('not supported'); end
      sf = 2;
      S = obj.Sigma/obj.k;
      xrange = [obj.mu-sf*S, obj.mu+sf*S, 0.01, sf*S];
    end
    
    function L = logprob(obj, X)
      % For 1d, L(i) = log p(X(i,:) | theta), where X(i,:) = [mu sigma]
      d = length(obj.mu);
      if d > 1, error('not supported'); end
      pgauss = mvnDist(obj.mu, obj.Sigma/obj.k);
      piw = invWishartDist(obj.dof, obj.Sigma);
      n = size(X,1);
      assert(size(X,2)==2);
      L = logprob(pgauss, X(:,1)) + logprob(piw, X(:,2));
    end
      
    
    function mm = marginal(obj, queryVar)
      % marginal(obj, 'Sigma') or marginal(obj, 'mu')
      switch lower(queryVar)
        case 'sigma'
          d = size(obj.Sigma,1);
          if d==1 
            mm = invGammaDist(obj.dof/2, obj.Sigma/2);
          else
            mm = invWishartDist(obj.dof, obj.Sigma);
          end
        case 'mu'
          d = length(obj.mu);
          v = obj.dof;
          if d==1
            mm = studentDist(v, obj.mu, obj.Sigma/(obj.k*v));
          else
            mm = mvtDist(v-d+1, obj.mu, obj.Sigma/(obj.k*(v-d+1)));
          end
        otherwise
          error(['unrecognized variable ' queryVar])
      end
    end
    
    

  end
    
  %% demos
  methods(Static = true)
    function demoPlot()
      mvnInvWishartDist.helperPlot(false);
      mvnInvWishartDist.helperPlot(true);
    end
    
     function h = helperPlot(useContour)
       if nargin < 1, useContour = false; end
       figure;
       nu = [1 1 5 5];
       sigma2 = 2*[1 1 1 1];
       %sigma2 = [1 1 1 0.5];
       mu = [0 0 0 0];
       k =[1 10 1 10];
       %sigma2 = sigma2 .* nu;
       N = length(nu);
       [nr nc] = nsubplots(N);
       for i=1:N
         subplot(nr, nr, i);
         p = mvnInvWishartDist('mu',mu(i), 'Sigma',sigma2(i), ...
           'dof', nu(i), 'k', k(i));
         plot(p, 'xrange', [-1 1 0.1 2], 'useContour', useContour);
         hold on
         str{i} = sprintf('NIW(%s=%3.1f, k=%3.1f, %s=%3.1f, %s=%3.1f)', ...
           'm', mu(i), k(i), '\nu', nu(i), 'S', sigma2(i));
         title(str{i})
         xlabel(sprintf('%s', '\mu'))
         ylabel(sprintf('%s', '\sigma^2'))
       end
     end
  end
    
end
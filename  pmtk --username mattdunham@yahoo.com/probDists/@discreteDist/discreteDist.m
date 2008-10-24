classdef discreteDist  < probDist

  properties
    probs;
    support;
  end


  methods
    function obj = discreteDist(probs, support)
      % probs is n*d, where probs(i,c) = p(Xi=c)
      if nargin == 0, probs = []; end
      if nargin < 2, support = 1:length(probs); end
      obj.probs = probs;
      obj.support = support;
    end

    function obj = computeProbs(obj)
      % for child classes
        obj.probs = exp(logprob(obj, obj.support));
    end
    
    function h=plot(obj, varargin)
      % plot a probability mass function as a histogram
      % handle = plot(pmf, 'name1', val1, 'name2', val2, ...)
      % Arguments are
      % plotArgs - args to pass to the plotting routine, default {}
      %
      % eg. plot(p,  'plotArgs', 'r')
      [plotArgs] = process_options(...
        varargin, 'plotArgs' ,{});
      if ~iscell(plotArgs), plotArgs = {plotArgs}; end
      if isempty(obj.probs), obj = computeProbs(obj); end
      if isvector(obj.probs), obj.probs = obj.probs(:)'; end % 1 distributin
      n = size(obj.probs, 1);
      for i=1:n
        h=bar(obj.probs(i,:), plotArgs{:});
        set(gca,'xticklabel',obj.support);
      end
    end

    function x = sample(obj, n)
      % X(i) = an integer drawn from obj's support
      if nargin < 2, n = 1; end
      if isempty(obj.probs), obj = computeProbs(obj); end
      p = obj.probs; cdf = cumsum(p); 
      [dum, y] = histc(rand(n,1),[0 cdf]);
      %y = sum( repmat(cdf, n, 1) < repmat(rand(n,1), 1, d), 2) + 1;
      x = obj.support(y);
    end

    function y = mode(obj)
      % y(i) = arg max probs(i,:)
      [junk, ndx] = max(obj.probs,[],2);
      y = obj.support(ndx);
    end
  end

  methods(Static = true)
    
    function test()
      p=discreteDist([0.3 0.2 0.5], [-1 0 1]);
      X=sample(p,1000);
      hh=hist(X,[-1 0 1])
       
      % two ternary variables
      p=discreteDist([0.3 0.2 0.5; 0.1 0.1 0.8]);
      plot(p);
    end
  end
  
end
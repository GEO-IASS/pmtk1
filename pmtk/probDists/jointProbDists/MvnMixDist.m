classdef MvnMixDist < MixtureDist
  % Mixture of Multivariate Normal Distributions


  methods

    function model = MvnMixDist(varargin)
      [nmixtures,mixingWeights,distributions,model.transformer,model.verbose,model.nrestarts] = process_options(varargin,...
        'nmixtures',[],'mixingWeights',[],'distributions',[],'transformer',[],'verbose',true,'nrestarts',model.nrestarts);
      if(~isempty(distributions)),nmixtures = numel(distributions);end

      if(isempty(mixingWeights) && ~isempty(nmixtures))
        mixingWeights = DiscreteDist('T',normalize(ones(nmixtures,1)));
      end
      model.mixingWeights = mixingWeights;
      if(isempty(distributions)&&~isempty(model.mixingWeights))
        distributions = copy(MvnDist(),nstates(model.mixingWeights),1);
      end
      model.distributions = distributions;

    end

    function model = setParamsAlt(model, mixingWeights, distributions)
      model.mixingWeights = colvec(mixingWeights);
      model.distributions = distributions;
    end


    function model = mkRndParams(model, d,K)
      model.distributions = copy(MvnDist(),K,1);
      model = mkRndParams@MixtureDist(model,d,K);
    end

    function mu = mean(m)
      mu = zeros(ndimensions(m),ndistrib(m));
      for k=1:ndistrib(m)
        mu(:,k) = colvec(m.distributions{k}.mu);
      end

      M = bsxfun(@times,  mu, rowvec(mean(m.mixingWeights)));
      mu = sum(M, 2);
    end

    function C = cov(m)
      mu = mean(m);
      C = mu*mu';
      for k=1:numel(m.distributions)
        mu = m.distributions{k}.mu;
        C = C + sub(mean(m.mixingWeights),k)*(m.distributions{k}.Sigma + mu*mu');
      end
    end


    function xrange = plotRange(obj, sf)
      if nargin < 2, sf = 3; end
      %if ndimensions(obj) ~= 2, error('can only plot in 2d'); end
      mu = mean(obj); C = cov(obj);
      s1 = sqrt(C(1,1));
      x1min = mu(1)-sf*s1;   x1max = mu(1)+sf*s1;
      if ndimensions(obj)==2
        s2 = sqrt(C(2,2));
        x2min = mu(2)-sf*s2; x2max = mu(2)+sf*s2;
        xrange = [x1min x1max x2min x2max];
      else
        xrange = [x1min x1max];
      end
    end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%{
    function mcmc = collapsedGibbs(model,data,varargin)
      [Nsamples, Nburnin, thin, verbose] = process_options(varargin, ...
        'Nsamples'  , 1000, ...
        'Nburnin'   , 500, ...
        'thin'    , 1, ...
        'verbose'   , false );
      [nobs,d] = size(data);
      K = numel(model.distributions);
      outitr = ceil((Nsamples - Nburnin) / thin);
      latent = zeros(nobs,outitr);
      keep = 1;

      fprintf('Initializing Gibbs sampler... \n')
      [latent(:,1), priorMuSigmaDist, SS] = initializeCollapsedGibbs(model,data);
      curlatent = latent(:,1);
      post = cell(nobs,K);
      marginalDist = cell(nobs,K);
      covtype = cell(1,K);

      for c=1:K
        covtype{c} = model.distributions{c}.covtype;
        switch class(priorMuSigmaDist{c})
          case 'MvnInvWishartDist'
            mu = priorMuSigmaDist{c}.mu; T = priorMuSigmaDist{c}.Sigma; dof = priorMuSigmaDist{c}.dof; k = priorMuSigmaDist{c}.k;
            marginalDist(:,c) = copy(MvtDist(dof - 1 + 1, mu, T*(k+1)/(k*(dof-d+1))), nobs, 1);
          case 'MvnInvGammaDist'
            a = priorMuSigmaDist{c}.a; b = priorMuSigmaDist{c}.b; m = priorMuSigmaDist{c}.mu; k = priorMuSigmaDist{c}.k;
            marginalDist(:,c) = copy(StudentDist(2*a, m, b.*(1+k)./a), nobs, 1);
        end
      end

      for itr=1:Nsamples
        fprintf('%d, ', itr)
        for obs=1:nobs
          kobs = curlatent(obs);
          xi = data(obs,:);
          prob = zeros(1,K);
          for k = 1:K
              [k0,v0,S0,m0] = updatePost(model,priorMuSigmaDist{k},SS,xi,kobs);
              kn = k0 + 1;
              mn = (k0*colvec(m0) + xi')/kn;
              switch covtype{k}
                case 'full'
                  vn = v0 + 1;
                  Sn = S0 + xi'*xi + k0/(k0+1)*(xi'-colvec(m0))*(xi'-colvec(m0))';
                  marginalDist{obs,k} = setParamsAlt(marginalDist{obs,k}, vn - d + 1, mu, Sn);
                case 'spherical'
                  an = v0 + d/2;
                  bn = S0 + 1/2*sum(diag( xi'*x' + k0/(k0+1)*(xi'-colvec(m0))*(xi'-colvec(m0))' ));
                  marginalDist{obs,k} = setParamsAlt(marginalDist{obs,k}, 2*an, mn, bn.*(1+kn)./an);
                case 'diagonal'
                  an = v0 + 1/2;
                  bn = diag( S0*eye(d) + 1/2*(xi'*xi + k0/(k0+1)*(xi'-colvec(m0))*(xi'-colvec(m0))'));
                  marginalDist{obs,k} = setParamsAlt(marginalDist{obs,k}, 2*an, mn, bn.*(1+kn)./an);
              end            
            nij = log(SS{k}.n);
            logmprob = logprob(marginalDist{obs,k}, xi);
            prob(k) =  nij + logmprob;
          end % for clust = 1:K
          prob = colvec(exp(normalizeLogspace(prob)));
          curlatent(obs) = sample(prob,1);
          [SS] = SSaddXi(model, covtype{curlatent(obs)}, SS, curlatent(obs), data(obs,:));
        end % obs=1:n
        if(itr > Nburnin && mod(itr, thin)==0)
          latent(:,keep) = curlatent;
          keep = keep + 1;
        end
      end
      fprintf('\n')
      mcmc.latent = latent;
      mcmc.loglik = zeros(1,outitr);
      mcmc.mix = zeros(K,outitr);
      mcmc.param = cell(K,outitr);
      param = cell(K,1);
      tmpdistrib = copy(MvnDist(),K,1);
      tmpmodel = MvnMixDist();
      for itr=1:outitr
        mix = histc(latent(:,itr), 1:K) / nobs;
        for k=1:K
          [mu, Sigma, domain] = convertToMvn( fit(MvnDist(), 'data', data(latent(:,itr) == k,:) ) );
          param{k} = struct('mu', mu, 'Sigma', Sigma);
          tmpdistrib{k} = setParamsAlt(tmpdistrib{k}, mu, Sigma);
        end
        mcmc.param(:,itr) = param;
        tmpmodel = setParamsAlt(tmpmodel, mix, tmpdistrib);
        mcmc.mix(:,itr) = mix;
        mcmc.loglik(:,itr) = logprobGibbs(tmpmodel,data,latent(:,itr));
      end
    end
%}
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    function mcmc = collapsedGibbs(model,data,varargin)
      [Nsamples, Nburnin, thin, verbose] = process_options(varargin, ...
        'Nsamples'  , 1000, ...
        'Nburnin'   , 500, ...
        'thin'    , 1, ...
        'verbose'   , false );
      [nobs,d] = size(data);
      K = numel(model.distributions);
      outitr = ceil((Nsamples - Nburnin) / thin);
      latent = zeros(nobs,outitr);
      keep = 1;

      fprintf('Initializing Gibbs sampler... \n')
      [latent(:,1), priorMuSigmaDist, SSxbar, SSn, SSXX, SSXX2] = initializeCollapsedGibbs(model,data);
      curlatent = latent(:,1);
      post = cell(nobs,K);
      marginalDist = cell(nobs,K);
      covtype = cell(1,K);

      for c=1:K
        covtype{c} = model.distributions{c}.covtype;
        switch class(priorMuSigmaDist{c})
          case 'MvnInvWishartDist'
            mu = priorMuSigmaDist{c}.mu; T = priorMuSigmaDist{c}.Sigma; dof = priorMuSigmaDist{c}.dof; k = priorMuSigmaDist{c}.k;
            marginalDist(:,c) = copy(MvtDist(dof - 1 + 1, mu, T*(k+1)/(k*(dof-d+1))), nobs, 1);
          case 'MvnInvGammaDist'
            a = priorMuSigmaDist{c}.a; b = priorMuSigmaDist{c}.b; m = priorMuSigmaDist{c}.mu; k = priorMuSigmaDist{c}.k;
            marginalDist(:,c) = copy(StudentDist(2*a, m, b.*(1+k)./a), nobs, 1);
        end
      end

      for itr=1:Nsamples
        fprintf('%d, ', itr)
        for obs=1:nobs
          kobs = curlatent(obs);
          xi = data(obs,:);
          prob = zeros(1,K);
          for k = 1:K
              [k0,v0,S0,m0] = updatePost(model,priorMuSigmaDist{k}, SSxbar, SSn, SSXX, SSXX2, xi,kobs);
              kn = k0 + 1;
              mn = (k0*colvec(m0) + xi')/kn;
              switch covtype{k}
                case 'full'
                  vn = v0 + 1;
                  Sn = S0 + xi'*xi + k0/(k0+1)*(xi'-colvec(m0))*(xi'-colvec(m0))';
                  marginalDist{obs,k} = setParamsAlt(marginalDist{obs,k}, vn - d + 1, mu, Sn);
                case 'spherical'
                  an = v0 + d/2;
                  bn = S0 + 1/2*sum(diag( xi'*x' + k0/(k0+1)*(xi'-colvec(m0))*(xi'-colvec(m0))' ));
                  marginalDist{obs,k} = setParamsAlt(marginalDist{obs,k}, 2*an, mn, bn.*(1+kn)./an);
                case 'diagonal'
                  an = v0 + 1/2;
                  bn = diag( S0*eye(d) + 1/2*(xi'*xi + k0/(k0+1)*(xi'-colvec(m0))*(xi'-colvec(m0))'));
                  marginalDist{obs,k} = setParamsAlt(marginalDist{obs,k}, 2*an, mn, bn.*(1+kn)./an);
              end
            nij = log(SSn(k));
            %margprob = marginal(postobs{obs,k});
            logmprob = logprob(marginalDist{obs,k}, xi);
            prob(k) =  nij + logmprob;
          end % for clust = 1:K
          prob = colvec(exp(normalizeLogspace(prob)));
          curlatent(obs) = sample(prob,1);
          [SSxbar, SSn, SSXX, SSXX2] = SSaddXi(model, covtype{curlatent(obs)}, SSxbar, SSn, SSXX, SSXX2, curlatent(obs), data(obs,:));
        end % obs=1:n
        if(itr > Nburnin && mod(itr, thin)==0)
          latent(:,keep) = curlatent;
          keep = keep + 1;
        end
      end
      fprintf('\n')
      mcmc.latent = latent;
      mcmc.loglik = zeros(1,outitr);
      mcmc.mix = zeros(K,outitr);
      mcmc.param = cell(K,outitr);
      param = cell(K,1);
      tmpdistrib = model.distributions;
      tmpmodel = model;
      for itr=1:outitr
        latent = mcmc.latent;
        mix = histc(latent(:,itr), 1:K) / nobs;
        for k=1:K
          [mu, Sigma, domain] = convertToMvn( fit(model.distributions{k}, 'data', data(latent(:,itr) == k,:) ) );
          param{k} = struct('mu', mu, 'Sigma', Sigma);
          tmpdistrib{k} = setParamsAlt(tmpdistrib{k}, mu, Sigma);
        end
        mcmc.param(:,itr) = param;
        tmpmodel = setParamsAlt(tmpmodel, mix, tmpdistrib);
        mcmc.mix(:,itr) = mix;
        mcmc.loglik(:,itr) = logprobGibbs(tmpmodel,data,latent(:,itr));
      end
    end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    function [obj,samples] = sampleParamGibbs(obj,X,latent)
      K = numel(obj.distributions); [n,d] = size(X);
      samples.mu = zeros(d,K);
      samples.Sigma = zeros(d,d,K);
      for k=1:K
        Xclus = X(latent == k,:);
        % we will sample first Sigma and then mu
        switch class(obj.distributions{k}.prior)
          case 'char'
            switch lower(obj.distributions{k}.prior)
              case 'none'
                error('MvnMixDist:sampleMuSigmaGibbs:invalidPrior','Warning, unable to sample mu, Sigma using Gibbs sampling when no prior distribution is specified for the distributions for each cluster');
              case 'nig'
                error('Not yet implemented');
              case 'niw'
                post = Mvn_MvnInvWishartDist(obj.distributions{k}.prior);
                joint = fit(post,'data', X(latent == k,:) );
                post = joint.muSigmaDist;
                % From post, get the values that we need for the marginal of Sigma for this distribution, and sample
                postSigma = InvWishartDist(post.dof + 1, post.Sigma);
                try
                  obj.distributions{k}.Sigma = sample(postSigma,1);
                catch ME
                  joint
                  X(latent == k,:)
                  rethrow(ME)
                end
                samples.Sigma(:,:,k) = obj.distributions{k}.Sigma;

                % Now, do the same thing for mu
                postMu = MvnDist(post.mu, obj.distributions{k}.Sigma / post.k);
                obj.distributions{k}.mu = sample(postMu,1);
                samples.mu(:,k) = rowvec(obj.distributions{k}.mu);
            end % of switch lower(prior)
          case 'MvnInvWishartDist'
            post = Mvn_MvnInvWishartDist(obj.distributions{k}.prior);
            joint = fit(post,'data', X(latent == k,:) );
            post = joint.muSigmaDist;
            % From post, get the values that we need for the marginal of Sigma for this distribution, and sample
            postSigma = InvWishartDist(post.dof + 1, post.Sigma);
            try
              obj.distributions{k}.Sigma = sample(postSigma,1);
            catch ME
              joint
              X(latent == k,:)
              rethrow(ME)
            end
            samples.Sigma(:,:,k) = obj.distributions{k}.Sigma;

            % Now, do the same thing for mu
            postMu = MvnDist(post.mu, obj.distributions{k}.Sigma / post.k);
            obj.distributions{k}.mu = sample(postMu,1);
            samples.mu(:,k) = rowvec(obj.distributions{k}.mu);
        end % of switch class(prior)
      end % of for statement
    end

  end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

  methods(Access = 'protected')

    function displayProgress(model,data,loglik,rr)
      figure(1000);
      clf
      t = sprintf('RR: %d, negloglik: %g\n',rr,-loglik);
      fprintf(t);
      if(size(data,2) == 2)
        nmixtures = numel(model.distributions);
        if(nmixtures == 2)
          colors = subd(predict(model,data),'T')';
          scatter(data(:,1),data(:,2),18,[colors(:,1),zeros(size(colors,1),1),colors(:,2)],'filled');
        else
          plot(data(:,1),data(:,2),'.','MarkerSize',10);
        end
        title(t);
        hold on;
        axis tight;
        for k=1:nmixtures
          f = @(x)sub(mean(model.mixingWeights),k)*exp(logprob(model.distributions{k},x));
          [x1,x2] = meshgrid(min(data(:,1)):0.1:max(data(:,1)),min(data(:,2)):0.1:max(data(:,2)));
          z = f([x1(:),x2(:)]);
          contour(x1,x2,reshape(z,size(x1)));
          mu = model.distributions{k}.mu;
          plot(mu(1),mu(2),'rx','MarkerSize',15,'LineWidth',2);
        end

      end
    end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%{
    function [latent, prior, SS] = initializeCollapsedGibbs(model,X)
      [n,d] = size(X);
      K = numel(model.distributions);
      latent = unidrnd(K,n,1);
      prior = cell(1,K);
      priorMvn = cell(1,K);

      SS = cell(K,1);
      %SSxi = cell(n,1);
      % since each MVN could have a different covariance structure, we need to do this.
      for k=1:K
        prior{k} = mkPrior(model.distributions{k},X);
        SS{k} = mkSuffStat(model.distributions{k}, X(latent == k,:));
        switch class(prior{k})
          case 'MvnInvWishartDist'
              priorMvn{k} = Mvn_MvnInvWishartDist(prior{k});
          case 'MvnInvGammaDist'
              priorMvn{k} = Mvn_MvnInvWishartDist(prior{k});
        end
        % Get sufficient statistics for each singleton so that we have it ready when fitting elsewhere
        %for obs=1:n
        %  SSxi{obs} = mkSuffStat(model.distributions{k}, X(obs,:));
        %end
      end
    end % initializeCollapsedGibbs

    function SS = SSaddXi(model, covtype, SS, knew, xi)
      % Add contribution of xi to SS for cluster knew
      SS{knew}.xbar = (SS{knew}.n*SS{knew}.xbar + xi')/(SS{knew}.n + 1);
      switch lower(covtype)
        case 'diagonal'
          SS{knew}.XX2 = diag(diag( (SS{knew}.n * SS{knew}.XX2 + xi'*xi) )) / (SS{knew}.n + 1);
          SS{knew}.XX = diag(diag( (SS{knew}.n * SS{knew}.XX2 + xi'*xi - (SS{knew}.n+1)*SS{knew}.xbar*SS{knew}.xbar') )) / (SS{knew}.n + 1);
        case 'spherical'
          SS{knew}.XX2 = diag(sum(diag( (SS{knew}.n*d * SS{knew}.XX2 + xi'*xi) )))/ ((SS{knew}.n + 1)*d);
          SS{knew}.XX = diag(sum(diag( (SS{knew}.n*d * SS{knew}.XX2 + xi'*xi - (SS{knew}.n+1)*SS{knew}.xbar*SS{knew}.xbar') )))/ ((SS{knew}.n + 1)*d);
        case 'full'
          SS{knew}.XX2 = (SS{knew}.n * SS{knew}.XX2 + xi'*xi) / (SS{knew}.n + 1);
          SS{knew}.XX = (SS{knew}.n * SS{knew}.XX2 + xi'*xi - (SS{knew}.n+1)*SS{knew}.xbar*SS{knew}.xbar') / (SS{knew}.n + 1);
      end
      SS{knew}.n = SS{knew}.n + 1;
    end

    %function post = updatePost(model, priorMvn, SS, xi, kobs, k);
    function [kn,vn,Sn,mn] = updatePost(model, priorMuSigmaDist, SS, xi, kobs)
        %K = numel(SS);
        %post = cell(1,K);
        n = SS{kobs}.n; d = length(xi);
        %for k=1:K
          xbar = (SS{kobs}.n*SS{kobs}.xbar - xi')/(SS{kobs}.n - 1);
          switch class(priorMuSigmaDist)
            case 'MvnInvWishartDist'
              k0 = priorMuSigmaDist.k; m0 = priorMuSigmaDist.mu;
              S0 = priorMuSigmaDist.Sigma; v0 = priorMuSigmaDist.dof;
              kn = k0 + n - 1;
              vn = v0 + n - 1;
              Sn = S0 + n*SS{kobs}.XX - xi'*xi+ (k0*(n-1))/(k0+n-1)*(xbar-colvec(m0))*(xbar-colvec(m0))';
              mn = (k0*colvec(m0) + n*xbar)/kn;
            case 'MvnInvGammaDist'
              k0 = priorMuSigmaDist.Sigma; m0 = priorMuSigmaDist.mu;
              S0 = priorMuSigmaDist.b; v0 = priorMuSigmaDist.a;
              switch lower(covtype)
                case 'spherical'
                  vn = v0 + n*d/2;
                  Sn = S0 + 1/2*sum(diag( n*SS{kobs}.XX - xi'*xi + (k0*(n-1))/(k0+n-1)*(xbar-colvec(m0))*(xbar-colvec(m0))' ));
                case 'diagonal'
                  vn = v0 + n/2;
                  Sn = diag( S0*eye(d) + 1/2*(n*SS{kobs}.XX -xi'*xi + (k0*(n-1))/(k0+n-1)*(xbar-colvec(m0))*(xbar-colvec(m0))'));
              end
          end
        %end
    end
%}

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    function [latent, prior, SSxbar, SSn, SSXX, SSXX2] = initializeCollapsedGibbs(model,X)
      [n,d] = size(X);
      K = numel(model.distributions);
      latent = unidrnd(K,n,1);
      prior = cell(K,1);
      priorMvn = cell(K,1);

      %SS = cell(K,1);
      %SSxi = cell(n,1);
      SSn = zeros(K,1);
      SSxbar = zeros(d,K);
      SSXX = zeros(d,d,K);
      SSXX2 = zeros(d,d,K);

      SSxin = zeros(K,1);
      SSxixbar = zeros(d,K);
      SSxiXX = zeros(d,d,K);
      SSxiXX2 = zeros(d,d,K);

      % since each MVN could have a different covariance structure, we need to do this.
      for k=1:K
        prior{k} = mkPrior(model.distributions{k},X);
        SS{k} = mkSuffStat(model.distributions{k}, X(latent == k,:));
        SSn(k) = SS{k}.n;
        SSxbar(:,k) = SS{k}.xbar;
        SSXX(:,:,k) = SS{k}.XX;
        SSXX2(:,:,k) = SS{k}.XX2;
        switch class(prior{k})
          case 'MvnInvWishartDist'
              priorMvn{k} = Mvn_MvnInvWishartDist(prior{k});
          case 'MvnInvGammaDist'
              priorMvn{k} = Mvn_MvnInvWishartDist(prior{k});
        end
        % Get sufficient statistics for each singleton so that we have it ready when fitting elsewhere
        for obs=1:n
          SSxi{obs} = mkSuffStat(model.distributions{k}, X(obs,:));
          SSxin(k) = SSxi{k}.n;
          SSxixbar(:,k) = SSxi{k}.xbar;
          SSxiXX(:,:,k) = SSxi{k}.XX;
          SSxiXX2(:,:,k) = SSxi{k}.XX2;
        end
      end
    end % initializeCollapsedGibbs

    function [SSxbar, SSn, SSXX, SSXX2] = SSaddXi(model, covtype, SSxbar, SSn, SSXX, SSXX2, knew, xi)
      % Add contribution of xi to SS for cluster knew
      SSxbar(:,knew) = (SSn(knew)*SSxbar(:,knew) + xi')/(SSn(knew) + 1);
      switch lower(covtype)
        case 'diagonal'
          SSXX2(:,:,knew) = diag(diag( (SSn(knew) * SSXX2(:,:,knew) + xi'*xi) )) / (SSn(knew) + 1);
          SSXX(:,:,knew) = diag(diag( (SSn(knew) * SSXX2(:,:,knew) + xi'*xi - (SSn(knew)+1)*SSxbar(:,knew)*SSxbar(:,knew)') )) / (SSn(knew) + 1);
        case 'spherical'
          SSXX2(:,:,knew) = diag(sum(diag( (SSn(knew)*d * SSXX2(:,:,knew) + xi'*xi) )))/ ((SSn(knew) + 1)*d);
          SSXX(:,:,knew) = diag(sum(diag( (SSn(knew)*d * SSXX2(:,:,knew) + xi'*xi - (SSn(knew)+1)*SSxbar(:,knew)*SSxbar(:,knew)') )))/ ((SSn(knew) + 1)*d);
        case 'full'
          SSXX2(:,:,knew) = (SSn(knew) * SSXX2(knew) + xi'*xi) / (SSn(knew) + 1);
          SSXX(:,:,knew) = (SSn(knew) * SSXX2(:,:,knew) + xi'*xi - (SSn(knew)+1)*SSxbar(:,knew)*SSxbar(:,knew)') / (SSn(knew) + 1);
      end
      SSn(knew) = SSn(knew) + 1;
    end


    function [kn,vn,Sn,mn] = updatePost(model, priorMuSigmaDist, SSxbar, SSn, SSXX, SSXX2, xi, kobs)
        %K = numel(SS);
        %post = cell(1,K);
        n = SSn(kobs); d = length(xi);
        %for k=1:K
          xbar = (SSn(kobs)*SSxbar(:,kobs) - xi')/(SSn(kobs) - 1);
          switch class(priorMuSigmaDist)
            case 'MvnInvWishartDist'
              k0 = priorMuSigmaDist.k; m0 = priorMuSigmaDist.mu;
              S0 = priorMuSigmaDist.Sigma; v0 = priorMuSigmaDist.dof;
              kn = k0 + n - 1;
              vn = v0 + n - 1;
              Sn = S0 + n*SSXX(:,:,kobs) - xi'*xi+ (k0*(n-1))/(k0+n-1)*(xbar-colvec(m0))*(xbar-colvec(m0))';
              mn = (k0*colvec(m0) + n*xbar)/kn;
            case 'MvnInvGammaDist'
              k0 = priorMuSigmaDist.Sigma; m0 = priorMuSigmaDist.mu;
              S0 = priorMuSigmaDist.b; v0 = priorMuSigmaDist.a;
              switch lower(covtype)
                case 'spherical'
                  vn = v0 + n*d/2;
                  Sn = S0 + 1/2*sum(diag( n*SSXX(:,:,kobs) - xi'*xi + (k0*(n-1))/(k0+n-1)*(xbar-colvec(m0))*(xbar-colvec(m0))' ));
                case 'diagonal'
                  vn = v0 + n/2;
                  Sn = diag( S0*eye(d) + 1/2*(n*SSXX(:,:,kobs) -xi'*xi + (k0*(n-1))/(k0+n-1)*(xbar-colvec(m0))*(xbar-colvec(m0))'));
              end
          end
        %end
    end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%{ Does anything call this function anymore??

     function [prob] = samplelatentgibbs(model, post, SS, SSxi, xi, kobs, obs)
      d = size(xi,2);
      K = numel(model.distributions);
      prob = zeros(K,1);
      SS{kobs}.xbar = (SS{kobs}.n*SS{kobs}.xbar - xi')/(SS{kobs}.n - 1);
      switch lower(model.distributions{kobs}.covtype)
        case 'diagonal'
          SS{kobs}.XX2 = diag(diag( (SS{kobs}.n * SS{kobs}.XX2 - xi'*xi) )) / (SS{kobs}.n - 1);
          SS{kobs}.XX = diag(diag( (SS{kobs}.n * SS{kobs}.XX2 - xi'*xi - (SS{kobs}.n-1)*SS{kobs}.xbar*SS{kobs}.xbar') )) / (SS{kobs}.n - 1);
          SS{kobs}.n = SS{kobs}.n - 1;
        case 'spherical'
          SS{kobs}.XX2 = diag(sum(diag( (SS{kobs}.n*d * SS{kobs}.XX2 - xi'*xi) )))/ ((SS{kobs}.n - 1)*d);
          SS{kobs}.XX = diag(sum(diag( (SS{kobs}.n*d * SS{kobs}.XX2 - xi'*xi - (SS{kobs}.n-1)*SS{kobs}.xbar*SS{kobs}.xbar') )))/ ((SS{kobs}.n - 1)*d);
          SS{kobs}.n = SS{kobs}.n - 1;
        case 'full'
          SS{kobs}.XX2 = (SS{kobs}.n * SS{kobs}.XX2 - xi'*xi) / (SS{kobs}.n - 1);
          SS{kobs}.XX = (SS{kobs}.n * SS{kobs}.XX2 - xi'*xi - (SS{kobs}.n-1)*SS{kobs}.xbar*SS{kobs}.xbar') / (SS{kobs}.n - 1);
          SS{kobs}.n = SS{kobs}.n - 1;
      end
      for k = 1:K
        priorlik = fit( post{obs,k}, 'suffStat', SS{k} );
        %switch class(prior{k})
        switch class(priorlik.muSigmaDist)
          case 'MvnInvWishartDist'
            %priorlik = fit( Mvn_MvnInvWishartDist(prior{k}), 'suffStat', SS{k} );
            postobs = fit( Mvn_MvnInvWishartDist(priorlik.muSigmaDist), 'suffStat', SSxi{obs} );
          case 'MvnInvGammaDist'
            %priorlik = fit( Mvn_MvnInvGammaDist(prior{k}), 'suffStat', SS{k} );
            postobs = fit( Mvn_MvnInvGammaDist(priorlik.muSigmaDist), 'suffStat', SSxi{obs} );
        end % switch class(prior{k})
        prob(k) = log(SS{k}.n) + logprob( marginal(postobs), xi );
      end % for clust = 1:K
      prob = colvec(exp(normalizeLogspace(prob)));
      %probobs = fit(probobs, 'suffStat', SS);
    end

%}

  end

end

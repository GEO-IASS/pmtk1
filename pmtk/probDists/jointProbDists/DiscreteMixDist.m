classdef DiscreteMixDist < MixtureDist
% A mixture of products of Discrete Distributions, (i.e. Naive Bayes structure,
% but with hidden class labels). Each product of Discrete distributions is
% represented as a single vectorized DiscreteDist object. This class can be used
% to create a mixture of Bernoullis, simply fit it on binary data. 


    
    methods
        
        function model = DiscreteMixDist(varargin)
            [nmixtures,mixingWeights,distributions,model.transformer,model.nrestarts,model.verbose] = process_options(varargin,...
                'nmixtures',[],'mixingWeights',[],'distributions',[],'transformer',[],'nrestarts',model.nrestarts,'verbose',true);
            if(isempty(mixingWeights) && ~isempty(nmixtures))
                mixingWeights = DiscreteDist('mu',normalize(ones(nmixtures,1)));
            end
            model.mixingWeights = mixingWeights;
            if(isempty(distributions)&&~isempty(model.mixingWeights))
                distributions = copy(DiscreteDist(),nstates(model.mixingWeights),1);
            end
            model.distributions = distributions;
           
        end
        
        function d = ndimensions(model)
           if(numel(model.distributions) > 0)
               d = ndistrib(model.distributions{1});
           else
               d = 0;
           end
            
        end
        
       
        
    end
    
    methods(Access = 'protected')
        
        function model = initializeEM(model,data)
            n = size(data,1);
            nmixtures = numel(model.distributions);
            perm = randperm(n);
            batchSize = max(1,floor(n/nmixtures));
            for k=1:nmixtures
               start = (k-1)*batchSize+1;
               initdata = data(perm(start:start+batchSize-1),:);  
               model.distributions{k} = fit(model.distributions{k},'data',initdata);
            end
            
        end
        
    end
    
    methods(Static = true)
        
        function testClass()
           % Cluster the mnist digits and visualize the cluster centers to see 
           % how well these resemble digits. 
           setSeed(1);
           lookfor = 2:4;    % decrease to save time - must be a subset of 0:9
           nexamples = 2000; % max 60000
           [X,junk,y,junk] = setupMnist(true,nexamples,0);
           clear junk;
           ndx = ismember(y,lookfor);
           X = double(X(ndx,:));
           clear y; % unsupervised!
           m = fit(DiscreteMixDist('nmixtures',numel(lookfor)),'data',X,'nrestarts',1); 
           for i=1:numel(lookfor)
              figure;
             imagesc(reshape(m.distributions{i}.mu(2,:),28,28)); 
           end
           placeFigures('Square',true)
           if(0)
               
              for i=1:numel(lookfor)
                  figure;
                  imagesc(reshape(mean(sample(m.distributions{i},500),1),28,28))
              end
               placeFigures;
           end
        end
        
        
    end
    
    
    
    
end
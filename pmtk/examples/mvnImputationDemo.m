function mvnImputationDemo()
%% Imputation for an MVN 
%#testPMTK

seeds = 0; % [0,1];
rnd = 0; % [0,1];
for i=1:length(seeds)
  setSeed(seeds(i));
  for j=1:length(rnd)
    r = rnd(j);
    helper(r);
  end
end
end

function helper(r)

d = 10;  pcMissing = 0.7;
model = mkRndParams(MvnDist(), d);
%model = mkRndParams(DiscreteProdDist('-ndims', d, '-nstates', 3));
n = 5;
Xfull = sample(model, n);

if r
  % Random missing pattern
  missing = rand(n,d) < pcMissing;
else
  % Make the first 3 stripes (features) be completely missing
  missing = false(n,d);
  missing(:, 1:floor(pcMissing*d)) = true;
end

Xmiss = Xfull;
Xmiss(missing) = NaN;
XmissImg = Xmiss;
XmissImg(missing) = 0;
Xhid = Xfull;
XhidImg = Xfull;
Xhid(~missing) = NaN;
XhidImg(~missing) = 0;
[Ximpute,V] = impute(model, Xmiss); % all the work happens here

nr = 2; nc = 2;

%{
figure; 
subplot(nr,nc,1); imagesc(Xfull); title('full data'); colorbar
%subplot(nr,nc,2); imagesc(missing); title('missing pattern'); colorbar
subplot(nr,nc,2); imagesc(XmissImg); title('observed data'); colorbar
subplot(nr,nc,3); imagesc(Ximpute); title('imputed mean'); colorbar
subplot(nr,nc,4); imagesc(XhidImg); title('hidden truth'); colorbar
%set(gcf,'position',[10 500 600 200])

hintonScale({Xfull}, {'-map', 'gray', '-title', 'full data'}, ...
  {Xmiss}, {'-map', 'Jet', '-title', 'observed'}, ...
  {Ximpute, V}, {'-title', 'imputed mean'}, ...
  {Xhid}, {'-title', 'hidden truth'});
%}

conf = 1./V;
conf(isinf(conf))=0;
conf

hintonScale({Xfull}, {'-map', 'jet', '-title', 'full data'}, ...
  {Xmiss}, {'-map', 'Jet', '-title', 'observed'}, ...
  {Ximpute, conf}, {'-title', 'imputed mean'}, ...
  {Xhid}, {'-title', 'hidden truth'});
%{
figure;
subplot(nr,nc,1); hintonScale(Xfull, ones(n,d));
title('full data');
ubplot(nr,nc,2); hintonScale(Xfull, 1-missing);
title('observed data');
subplot(nr,nc,3); hintonScale(Ximpute, V); 
title('imputed mean (color)/ variance (size)');
subplot(nr,nc,4); hintonScale(Xfull, missing);
title('hidden truth');
%}


%{
figure;
subplot(nr,nc,1); hintonScale(Xfull, ones(n,d), '-map', gray);
title('full data'); colorbar
subplot(nr,nc,2); hintonScale(Xfull, 1-missing, '-map', 'gray');
title('observed data'); colorbar
subplot(nr,nc,3); hintonScale(Ximpute, V, '-map', 'gray');
title('imputed mean (color)/ variance (size)'); colorbar
subplot(nr,nc,4); hintonScale(Xfull, missing, '-map', 'gray');
title('hidden truth'); colorbar
%}



end

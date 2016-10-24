function [ input, proj, center, scale ] = get( obj, idx, cam )
% This does not produce the exact output as the get() in h36m.lua
%   1. input is of type uint8 with values in range [0 255]

% Load image
im = loadImage(obj, idx, cam);

% Get center and scale
[center, scale] = getCenterScale(obj, im);

% Transform image
im = obj.img.crop(im, center, scale, 0, obj.inputRes);

% % Get projection
% pts = permute(obj.part(idx,:,:),[2 3 1]);
% vis = permute(obj.visible(idx,:),[2 1]);
% proj = zeros(size(pts));
% for i = 1:size(pts,1)
%     if vis(i)
%         proj(i,:) = obj.img.transform(pts(i,:), center, scale, 0, obj.outputRes, false, false);
%     end
% end
proj = [];

% % Generate heatmap
% hm = zeros(obj.outputRes,obj.outputRes,size(pts,1));
% for i = 1:size(pts,1)
%     if vis(i)
%         hm(:,:,i) = obj.img.drawGaussian(hm(:,:,i),round(proj(i,:)),2);
%     end
% end
% hm = permute(hm,[3 1 2]);

% Set input
if obj.hg
    input = im;
else
    % input = hm;
end

end

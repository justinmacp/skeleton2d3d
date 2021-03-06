--
--  Copyright (c) 2016, Facebook, Inc.
--  All rights reserved.
--
--  This source code is licensed under the BSD-style license found in the
--  LICENSE file in the root directory of this source tree. An additional grant
--  of patent rights can be found in the PATENTS file in the same directory.
--
--  Multi-threaded data loader
--

local Threads = require 'threads'
Threads.serialization('threads.sharedserialize')

local M = {}
local DataLoader = torch.class('skeleton2d3d.DataLoader', M)

function DataLoader.create(opt)
   -- The train and val loader
   local loaders = {}

   for i, split in ipairs{'train', 'val'} do
      -- local dataset = Dataset(opt, split)
      -- loaders[split] = M.DataLoader(dataset, opt, split)
      -- loaders[split] = M.DataLoader(opt, split)
      local Dataset = require('lib/datasets/' .. opt.dataset)
      local dataset = Dataset(opt, split)
      loaders[split] = M.DataLoader(dataset, opt, split)
   end

   -- return table.unpack(loaders)
   return loaders
end

function DataLoader:__init(dataset, opt, split)
-- function DataLoader:__init(opt, split)
   local manualSeed = opt.manualSeed
   local function init()
      -- require('lib/datasets/' .. opt.dataset)
      -- We should have initialize dataset in creat(). This is currently not
      -- possible since the used hdf5 library will throw errors if we do that.
      local Dataset = require('lib/datasets/' .. opt.dataset)
      -- dataset = Dataset(opt, split)
   end
   local function main(idx)
      -- This matters due to the thread-dependent randomness from data synthesis
      if manualSeed ~= 0 then
         torch.manualSeed(manualSeed + idx)
      end
      torch.setnumthreads(1)
      _G.dataset = dataset
      return dataset:size()
   end

   local threads, outputs = Threads(opt.nThreads, init, main)
   self.threads = threads
   self.__size = outputs[1][1]
   self.batchSize = opt.batchSize
end

function DataLoader:size()
   return math.ceil(self.__size / self.batchSize)
end

function DataLoader:sizeDataset()
   return self.__size
end

function DataLoader:run(kwargs)
   local threads = self.threads
   local size, batchSize = self.__size, self.batchSize
   local perm
   assert(kwargs ~= nil and kwargs.train ~= nil)
   if kwargs.train then
      perm = torch.randperm(size)
   else
      batchSize = 1
      perm = torch.range(1, size)
   end

   local idx, sample = 1, nil
   local function enqueue()
      while idx <= size and threads:acceptsjob() do
         local indices = perm:narrow(1, idx, math.min(batchSize, size - idx + 1))
         threads:addjob(
            function(indices)
               local sz = indices:size(1)
               local input, imageSize
               local repos, reposSize
               local trans, transSize
               local focal
               local hmap, hmapSize
               local proj, projSize
               local gtpts, gtptsSize
               local center
               local scale
               for i, idx in ipairs(indices:totable()) do
                  local sample = _G.dataset:get(idx, kwargs.train)
                  if not input then
                     imageSize = sample.input:size():totable()
                     if _G.dataset.hg and not kwargs.train then
                        table.remove(imageSize, 1)
                        input = torch.FloatTensor(sz, 2, unpack(imageSize))
                     else
                        input = torch.FloatTensor(sz, unpack(imageSize))
                     end
                  end
                  if not repos then
                     reposSize = sample.repos:size():totable()
                     repos = torch.FloatTensor(sz, unpack(reposSize))
                  end
                  if not trans then
                     transSize = sample.trans:size():totable()
                     trans = torch.FloatTensor(sz, unpack(transSize))
                  end
                  if not focal then
                     focal = torch.FloatTensor(sz, 1)
                  end
                  if not hmap then
                     hmapSize = sample.hmap:size():totable()
                     hmap = torch.FloatTensor(sz, unpack(hmapSize))
                  end
                  if not proj then
                     projSize = sample.proj:size():totable()
                     proj = torch.FloatTensor(sz, unpack(projSize))
                  end
                  if not gtpts then
                     gtptsSize = sample.gtpts:size():totable()
                     gtpts = torch.FloatTensor(sz, unpack(gtptsSize))
                  end
                  if not center then
                     center = torch.FloatTensor(sz, 2)
                  end
                  if not scale then
                     scale = torch.FloatTensor(sz, 1)
                  end
                  input[i] = sample.input
                  repos[i] = sample.repos
                  trans[i] = sample.trans
                  focal[i] = sample.focal
                  hmap[i] = sample.hmap
                  proj[i] = sample.proj
                  gtpts[i] = sample.gtpts
                  center[i] = sample.center
                  scale[i] = sample.scale
               end
               if _G.dataset.hg and not kwargs.train then
                  input = input:view(2, unpack(imageSize))
               end
               collectgarbage()
               return {
                  index = indices:int(),
                  input = input,
                  repos = repos,
                  trans = trans,
                  focal = focal,
                  hmap = hmap,
                  proj = proj,
                  gtpts = gtpts,
                  center = center,
                  scale = scale,
               }
            end,
            function(_sample_)
               sample = _sample_
            end,
            indices
         )
         idx = idx + batchSize
      end
   end

   local n = 0
   local function loop()
      enqueue()
      if not threads:hasjob() then
         return nil
      end
      threads:dojob()
      if threads:haserror() then
         threads:synchronize()
      end
      enqueue()
      n = n + 1
      return n, sample
   end

   return loop
end

return M.DataLoader
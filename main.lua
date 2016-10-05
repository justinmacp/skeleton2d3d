require 'cutorch'

local DataLoader = require 'lib/dataloader'
local models = require 'lib/models/init'
local Trainer = require 'lib/train'
local opts = require 'lib/opts'
local checkpoints = require 'lib/checkpoints'

local opt = opts.parse(arg)

-- Load previous checkpoint, if it exists
local checkpoint, optimState, opt = checkpoints.latest(opt)

cutorch.setDevice(opt.GPU)
torch.manualSeed(opt.manualSeed)
cutorch.manualSeedAll(opt.manualSeed)

-- Create model
local model, criterion = models.setup(opt, checkpoint)

-- Data loading
local loaders = DataLoader.create(opt)

-- The trainer handles the training loop and evaluation on validation set
local trainer = Trainer(model, criterion, opt, optimState)

local startEpoch = checkpoint and checkpoint.epoch + 1 or 1
for epoch = startEpoch, opt.nEpochs do
  -- Train for a single epoch
  trainer:train(epoch, loaders)

  -- Run model on validation set
  local iter = loaders['train']:size()
  local err = trainer:test(epoch, iter, loaders, 'val')

  checkpoints.save(epoch, model, trainer.optimState, nil, opt)
end

-- Predict with the final model
trainer:predict(loaders, 'train')
trainer:predict(loaders, 'val')
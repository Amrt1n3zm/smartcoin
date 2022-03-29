#!/usr/bin/python
import pyopencl as cl

for p in cl.get_platforms():
  devices = p.get_devices(device_type=cl.device_type.GPU)
  for i in xrange(len(devices)):
    print '%d\tGPU[%d]\t0\tgpu' % (i,i)




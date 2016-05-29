#Loads input files and dumps to an output file

import os, os.path, json

inputs = {}
if os.path.exists('/inputs'):
	for f in os.listdir('/inputs'):
		with open(os.path.join('/inputs', f)) as data:
			d = json.load(data)
			inputs[f] = d

if os.path.exists('/outputs'):
	outfile = '/outputs/output1'
	with open(outfile, 'w') as outfile:
		json.dump(inputs, outfile)
print(json.dumps(inputs))

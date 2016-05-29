#Loads input files and dumps to an output file
from __future__ import print_function
import sys
import os, os.path, json
import codecs

print('Starting python in container!')

inputs = {}
if os.path.exists('/inputs'):
	print('/inputs', os.listdir('/inputs'))
	for f in os.listdir('/inputs'):
		try:
			fileName = os.path.join('/inputs', f)
			print('fileName', fileName)
			fp = codecs.open(fileName, "r", "utf-8")
			text = fp.read()
			print('text', text)
			d = json.loads(text)
			inputs[f] = d
		except RuntimeError as e:
			print("ERROR: ", e, file=sys.stderr)

else:
	print('No folder=/inputs')

if os.path.exists('/outputs'):
	outfile = '/outputs/output1'
	with open(outfile, 'w') as outfile:
		json.dump(inputs, outfile)
else:
	print('No folder=/outputs')

print(json.dumps(inputs))
print('THIS IS STDOUT')
print("THIS IS STDERR", file=sys.stderr)

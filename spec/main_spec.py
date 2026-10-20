'''
Main specification index for lean-xv6
'''

from libspec import Spec
from . import app, mcl, trust, unicompiler, layers, trap, stage_w, kalloc, proc, user, shell, lifecycle

class MainSpec(Spec):
    def modules(self):
        return [app, mcl, trust, unicompiler, layers, trap, stage_w, kalloc, proc, user, shell, lifecycle]

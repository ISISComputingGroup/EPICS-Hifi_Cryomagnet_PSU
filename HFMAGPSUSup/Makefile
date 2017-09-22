TOP=..
include $(TOP)/configure/CONFIG
#=======================================

# Install .dbd and .db files

DATA += devHFMAGPSU.proto

DBD += fsm.dbd

# Sequence file
SRCS += fsm.st

LIBRARY_IOC = HFMAGPSU
HFMAGPSU_LIBS += seqDev seq pv
HFMAGPSU_LIBS += $(EPICS_BASE_IOC_LIBS)

#=======================================
include $(TOP)/configure/RULES

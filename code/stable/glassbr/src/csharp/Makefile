ifeq "$(OS)" "Windows_NT"
    TARGET_EXTENSION=.exe
    CSC=csc
else
    UNAME_S := $(shell uname -s)
    ifeq ($(UNAME_S), Linux)
        TARGET_EXTENSION=
        CSC=mcs
    endif
    ifeq ($(UNAME_S), Darwin)
        TARGET_EXTENSION=
        CSC=mcs
    endif
endif

build: GlassBR$(TARGET_EXTENSION)

GlassBR$(TARGET_EXTENSION): Control.cs InputParameters.cs InputFormat.cs DerivedValues.cs InputConstraints.cs OutputFormat.cs Calculations.cs ReadTable.cs Interpolation.cs
	$(CSC) -out:GlassBR$(TARGET_EXTENSION) Control.cs InputParameters.cs InputFormat.cs DerivedValues.cs InputConstraints.cs OutputFormat.cs Calculations.cs ReadTable.cs Interpolation.cs

run: build
	./GlassBR$(TARGET_EXTENSION) $(RUNARGS)

doc: doxConfig Control.cs InputParameters.cs InputFormat.cs DerivedValues.cs InputConstraints.cs OutputFormat.cs Calculations.cs ReadTable.cs Interpolation.cs
	doxygen doxConfig

.PHONY: build run doc

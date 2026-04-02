CC = g++

CCFLAGS = -std=c++17 -Wall -O3 -DNDEBUG -I../../lib
#CCFLAGS = -std=c++17 -Wall -O3 -g -I../../lib
#CCFLAGS = -std=c++17 -Wall -O3 -g -DALLSTATS -I../../lib
LDFLAGS = 
LOADLIBES = -lm
MLBFLAGS = -DMLB

SRCS = main.cc sp.cc smartq.cc parser_gr.cc timer.cc
HDRS = sp.h nodearc.h smartq.h stack.h values.h
CODES = sq mbp sqC mbpC

all: $(CODES)

sq: $(SRCS) $(HDRS) parser_ss.cc
	$(CC) $(CCFLAGS) -o sq $(SRCS) parser_ss.cc $(LOADLIBES)

sqC: $(SRCS) $(HDRS) parser_ss.cc
	$(CC) $(CCFLAGS) -DCHECKSUM -o sqC $(SRCS) parser_ss.cc $(LOADLIBES)

mbp: $(SRCS) $(HDRS) parser_p2p.cc
	$(CC) $(CCFLAGS) $(MLBFLAGS) -DSINGLE_PAIR -o mbp $(SRCS) parser_p2p.cc $(LOADLIBES)

mbpC: $(SRCS) $(HDRS) parser_p2p.cc
	$(CC) $(CCFLAGS) $(MLBFLAGS) -DCHECKSUM -DSINGLE_PAIR -o mbpC $(SRCS) parser_p2p.cc $(LOADLIBES)

clean:
	rm -f *~ sq mbp sqC mbpC

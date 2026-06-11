TESTING_FW = /Library/Developer/CommandLineTools/Library/Developer/Frameworks
TESTING_LIB = /Library/Developer/CommandLineTools/Library/Developer/usr/lib

TEST_FLAGS = \
	-Xswiftc "-F" -Xswiftc "$(TESTING_FW)" \
	-Xlinker "-F" -Xlinker "$(TESTING_FW)" \
	-Xlinker "-framework" -Xlinker "Testing" \
	-Xlinker "-rpath" -Xlinker "$(TESTING_FW)" \
	-Xlinker "-rpath" -Xlinker "$(TESTING_LIB)"

.PHONY: test
test:
	swift test $(TEST_FLAGS)

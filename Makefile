all:
	as --64 server.s -o server.o
	ld -m elf_x86_64 server.o -o server

clean:
	rm -f *.o server

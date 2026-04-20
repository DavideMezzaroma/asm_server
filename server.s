.intel_syntax noprefix
.globl _start

.section .text

_start:
	#socket(AF_INET, SOCK_STREAM, 0)
	mov rdi, 2	#mov rdi, AF_INET
	mov rsi, 1	#mov rsi, SOCK_STREAM
	mov rdx, 0	#default protocol
   	mov rax, 41     # SYS_socket
	syscall
	mov r12, rax	#save sockfd for later
	#from here rax holds the sockfd

    # setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, true, sizeof(int))
    push 1
    mov rdi, r12
    mov rsi, 1      # SOL_SOCKET
    mov rdx, 2		#SO_REUSEADDR
    mov r10, rsp
    mov r8, 4
    mov rax, 54     # SYS_setsockopt
    syscall
    pop rax

	#sockaddr struct:	AF_INET, 80, any IP_ADDR
	sub rsp, 32		#make room for 4byte struct
	lea rsi, [rsp]		#load rsp address
	mov WORD PTR [rsi], 2		#AF_INET at start of struct
	#mov WORD PTR [rsi+2], 0x5000	#port 80 second arg of struct -- deprecated
	mov WORD PTR [rsi+2], 0x901F	#port 8080 second arg of struct
	mov DWORD PTR [rsi+4], 0	#any address, last arg of struct
	mov QWORD PTR [rsi+8], 0	#padding, struct must be 16 bytes

	#bind(sockfd, sockaddr*, sockaddr_size)
	mov rdi, r12	#sockfd into first argument of bind
	lea rsi, [rsp] 	#rsi holds the address to the struct
	mov rdx, 16	#holds the struct size
	mov rax, 49	#SYS_bind
	syscall
	
	#listen(sockfd, max_connections)
	mov rdi, r12	#sockfd into first argument of listen
	mov rsi, 0	#backlog -> max num connections
	mov rax, 50	#SYS_listen
	syscall
	
_PARENT_LOOP:		#parent accept connection, forks, close socket and restart.

	#accept(sockfd, NULL, NULL)
	mov rdi, r12	#rdi holds sockfd
	mov rsi, 0
	mov rdx, 0
	mov rax, 43	#SYS_accept
	syscall
	mov r9, rax	#rdi holds clientfd

	#fork()
	mov rax, 57	#SYS_fork
	syscall
	cmp rax, 0
	jl _PARENT_LOOP

	cmp rax, 0	#if ret value of fork == 0 -> child is executing
	jz _CHILD_BLOCK

	#close(clientfd)
	mov rdi, r9
	mov rax, 3 	#SYS_close, (rdi still holds clientfd)
	syscall

	#loop for other sequential connections
	jmp _PARENT_LOOP

_CHILD_BLOCK:		#child processes the connection

	#close(socketfd)
	mov rdi, r12
	mov rax, 3 	#SYS_close, (rdi still holds clientfd)
	syscall

	#read(clientfd, NULL, NULL)
	mov rdi, r9
	sub rsp, 1024
	mov rsi, rsp
	mov rdx, 1024
	mov rax, 0	#SYS_read
	syscall
	mov r14, rax	#set r14 as the length of the input for POST method

	cmp BYTE PTR [rsp], 71
	je _GET_BLOCK

_POST_BLOCK:
	lea r11, [rsp+5]	#save r11 as the pointer to the start of the path (excluding POST )
	mov rdi, r11

_FIND_POST_PATH:
	cmp BYTE PTR [rdi], 0x20	#check if pointed character is space
	je _FOUND_POST_PATH	
	cmp BYTE PTR [rdi], 0x00	#check if pointed character is null
	je _FOUND_POST_PATH
	inc rdi
	jmp _FIND_POST_PATH

_FOUND_POST_PATH:
	mov BYTE PTR [rdi], 0	#set \0 after POST /path/to/requested/resources

	#open(file_path, O_RDONLY, 0777)
	mov rdi, r11	#set rdi as the string obtained with read()
	mov rsi, 01		#set O_WRONLY
	xor rsi, 0100	#second param = O_WRONLY | O_CREAT
	mov rdx, 0777	#set last param to 0777
	mov rax, 2		#SYS_open
	syscall
	mov r12, rax	#save file_fd in r12
	
	mov r15, 0
_START_POST_PARSE:
	cmp BYTE PTR [rsp+r15], 0x0D
	jne _NEXT_CHAR
	cmp BYTE PTR [rsp+r15+1], 0x0A
	jne _NEXT_CHAR
	cmp BYTE PTR [rsp+r15+2], 0x0D
	jne _NEXT_CHAR
	cmp BYTE PTR [rsp+r15+3], 0x0A
	je _FOUND_HEADER 

_NEXT_CHAR:
	inc r15
	jmp _START_POST_PARSE
	
_FOUND_HEADER:
	mov rbx, r15
	add rbx, 4

	mov r13, r14
	sub r13, rbx		#here r13 has the size of POST payload

	#write(file_fd, payload, payload_size)
	mov rdi, r12
	#sub r14, r13
	lea rsi, [rsp+rbx]
	mov rdx, r13
	mov rax, 1
	syscall

	#close(file_fd)
	mov rdi, r12
	mov rax, 3
	syscall
	
	#write(clietfd, HTTP_resp, resp_len)
	mov rdi, r9			#set clientfd as first arg of write
	lea rsi, [rip+ok200]	#loads the HTTP_resp addr into second arg of write
	mov rdx, 19			#len of HTTP_resp
	mov rax, 1			#SYS_write
	syscall

	jmp _EXIT
	
_GET_BLOCK:
	lea r11, [rsp+4]	#save r11 as the pointer to the start of the path (excluding GET )
	mov rdi, r11

	cmp BYTE PTR [r11], '/'
	jne _FIND_GET_PATH
	inc r11

_FIND_GET_PATH:
	cmp BYTE PTR [rdi], 0x20	#check if pointed character is space
	je _FOUND_GET_PATH	
	cmp BYTE PTR [rdi], 0x00	#check if pointed character is null
	je _FOUND_GET_PATH
	inc rdi
	jmp _FIND_GET_PATH

_FOUND_GET_PATH:
	mov BYTE PTR [rdi], 0	#set \0 after GET /path/to/requested/resources

	#open(file_path, O_RDONLY, NULL)
	mov rdi, r11	#set rdi as the string obtained with read()
	mov rsi, 0	#set O_RDONLY
	mov rdx, 0
	mov rax, 2	#SYS_open
	syscall

	#file_path not found => error 404
	cmp rax, 0
	jl _ERROR_404
	mov r12, rax	#save file_fd in r12

	#read(file_fd, buff, buff_size)
	mov rdi, r12	#set file_fd as first arg of read
	sub rsp, 2048	#allocate space for reading file
	mov rsi, rsp	#set buff addr as second arg of read
	mov rdx, 2048	#set buff size as last arg of read
	mov rax, 0	#SYS_read
	syscall
	mov r15, rax	#save file output to r15

	#same thing but reusing the 1024 bytes already allocated
	#mov rdi, r12	#set file_fd as first arg of read
	#lea rsi, [rsp]
	#mov rdx, 1024
	#mov rax, 0
	#syscall
	#mov r15, rax
    #
	
	#close(file_fd)
	mov rdi, r12
	mov rax, 3	#SYS_close
	syscall

	#send header -> write(clietfd, HTTP_resp, resp_len)
	mov rdi, r9	#set clientfd as first arg of write
	lea rsi, [rip+ok200]	#loads the HTTP_resp addr into second arg of write
	mov rdx, 19	#len of HTTP_resp
	mov rax, 1	#SYS_write
	syscall
	
	#write(clientfd, file_output, file_output_len)
	mov rdi, r9	#clietfd as first param for write
	lea rsi, [rsp]	#get the pointer to file output as second param for write
	mov rdx, r15	#set file_out_len as last arg of write
	mov rax, 1	#SYS_write
	syscall

	jmp _EXIT

_ERROR_404:
	#write(clientfd, ERROR_404, error_len)
	mov rdi, r9
	lea rsi, [rip+error404]
	mov rdx, 24
	mov rax, 1
	syscall
	jmp _EXIT
	

_EXIT:
	#exit(0)
	mov rdi, 0
	mov rax, 60
	syscall

.section .data
ok200:		.ascii "HTTP/1.0 200 OK\r\n\r\n"
error404: 	.ascii "HTTP/1.0 404 Not Found\r\n"

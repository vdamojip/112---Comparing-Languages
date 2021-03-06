#!/usr/bin/env mzscheme -qr
;#!/afs/cats.ucsc.edu/courses/cmps112-wm/usr/racket-5.1/bin/mzscheme -qr
;; AUTHORS
;;   Will Crawford <wacrawfo@ucsc.edu>
;;   Ben Ross     <bpross@ucsc.edu>
;;   Based on code by Wesley Mackey
;; NAME
;;   sbi.scm - silly basic interpreter
;; SYNOPSIS
;;   sbi.scm filename.sbir
;; DESCRIPTION
;;   The file mentioned in argv[1] is read and assumed to be an
;;   SBIR program, which is the executed.  Currently it is only
;;   printed.
;; == Mackey's functions =======================================
; Define *stderr*
(define *stderr* (current-error-port))
; Function: Find the basename of the filename provided.
(define *run-file*
   (let-values
      (((dirpath basepath root?)
         (split-path (find-system-path 'run-file))))
      (path->string basepath)))
; Function: Exit and print the error provided.
(define (die list)
   (for-each (lambda (item) (display item *stderr*)) list)
   (newline *stderr*)
   (exit 1))
; Function: Print usage information and die.
(define (usage-exit)
   (die `("Usage: " ,*run-file* " filename")))
; Function: Read in the file.
(define (readlist-from-inputfile filename)
   (let ((inputfile (open-input-file filename)))
       (if (not (input-port? inputfile))
          (die `(,*run-file* ": " ,filename ": open failed"))
          (let ((program (read inputfile)))
              (close-input-port inputfile)
                   program))))
(define *symbol-table* (make-hash)) ; Symbol hash table
(define (symbol-put! key value)
        (hash-set! *symbol-table* key value))
;; ==== Our functions ==========================================
; Initialize the symbol table.
(for-each
    (lambda (pair)
            (symbol-put! (car pair) (cadr pair)))
    `(
        (log10_2 0.301029995663981195213738894724493026768189881)
        (sqrt_2  1.414213562373095048801688724209698078569671875)
        (e       2.718281828459045235360287471352662497757247093)
        (pi      3.141592653589793238462643383279502884197169399)
        (div     ,(lambda (x y) (floor (/ x y))))
        (log10   ,(lambda (x) (/ (log x) (log 10.0))))
        (mod     ,(lambda (x y) (- x (* (div x y) y))))
        (quot    ,(lambda (x y) (truncate (/ x y))))
        (rem     ,(lambda (x y) (- x (* (quot x y) y))))
        (<>      ,(lambda (x y) (not (= x y))))
        (+ ,+) (- ,-) (* ,*) (/ ,/) (abs ,abs) 
        (<= ,<=) (>= ,>=) (= ,=) (> ,>) (tan ,tan)
        (< ,<) (^ ,expt) (atan ,atan) (sin ,sin) (cos ,cos)
        (ceil ,ceiling) (exp ,exp) (floor ,floor)
        (asin ,asin) (acos ,acos) (round ,round)
        (log ,log) (sqrt ,sqrt)))
(define n-hash (make-hash)) ; Native function translation table
(define l-hash (make-hash)) ; Label hash table
(define (h_eval expr) ; Evaluates expressions.
  ;(printf "DEBUG: h_Evaluating...~n")
  ;(printf "       ~s~n" expr)
  (cond
    ((string? expr)
      ;(printf "       is a string~n")
      expr)
    ((number? expr)
      ;(printf "       is a number~n")
      expr)
    ((hash-has-key? *symbol-table* expr)
      ;(printf "       is a hash key~n")
      (hash-ref *symbol-table* expr))
    ((list? expr)
      ;(printf "       is a list~n")
      (if (hash-has-key? *symbol-table* (car expr))
        (let((head (hash-ref *symbol-table*  (car expr))))
          (cond 
            ((procedure? head)
             (apply head (map (lambda (x) (h_eval x)) (cdr expr))))
            ((vector? head)
             ;(printf "It's a vector.")
             (vector-ref head (cadr expr)))
            ((number? head)
             ;(printf "It's a number.~n")
             head)
            (else
              (die "Fatal: Broken symbol table."))))
        (die (list "Fatal error: " 
                   (car expr) " not in symbol table!\n"))))))

(define (sb_print expr) ; PRINTs. Only called if there are print args.
   (map (lambda (x) (display (h_eval x))) expr)
   (newline))

(define (sb_dim expr) ; Declare an array.
  (set! expr (car expr))
  (let((arr (make-vector (h_eval (cadr expr)) (car expr))))
    (symbol-put! (car expr) (+ (h_eval (cadr expr)) 1))))

(define (sb_let expr) ; Assign a variable.
  (symbol-put! (car expr) (h_eval (cadr expr))))
(define (sb_input2 expr count)
  (if (null? expr)
    count
     (let ((input (read)))
        (if (eof-object? input)
          -1
          (begin
            (symbol-put! (car expr) input)
            (set! count (+ 1 count))
            (sb_input2 (cdr expr) count))))))

(define (sb_input expr) ; Take input.
  (symbol-put! 'inputcount 0)
  (if (null? (car expr))
    (symbol-put! 'inputcount -1)
    (begin
    (symbol-put! 'inputcount (sb_input2 expr 0)))))

; Function: Execute a line passed by eval-line.
(define (exec-line instr program line-nr) ; Execute a line.
  (when (not (hash-has-key? n-hash (car instr))) ; Die if invalid.
        (die "~s is not a valid instruction." (car instr)))
  (cond
        ((eq? (car instr) 'goto)
         (eval-line program (hash-ref l-hash (cadr instr))))
        ((eq? (car instr) 'if)
         (if (h_eval (car (cdr instr)))
            (eval-line program (hash-ref l-hash (cadr (cdr instr))))
           (eval-line program (+ line-nr 1))))
        ((eq? (car instr) 'print)
         (if (null? (cdr instr))
           (newline)
           (sb_print (cdr instr))) ; Bad identifier?!
           (eval-line program (+ line-nr 1)))
        (else
          ((hash-ref n-hash (car instr)) (cdr instr))
          (eval-line program (+ line-nr 1)))))

; Function: Walk through program and execute it. 
; This function takes a line number to execute.
(define (eval-line program line-nr) ; Parse a line.
   (when (> (length program) line-nr)
    ;(printf "DEBUG: Executing line ~a of ~a.~n" 
    ;        line-nr (length program))
    ;(printf "       ~s~n" (list-ref program line-nr))
    (let((line (list-ref program line-nr)))
    (cond
      ((= (length line) 3)
       (set! line (cddr line))
       (exec-line (car line) program line-nr))
      ((and (= (length line) 2) (list? (cadr line)))
       (set! line (cdr line))
       (exec-line (car line) program line-nr))
      (else 
        (eval-line program (+ line-nr 1)))
    ))))
; Function: Find the length of a list.
(define length
   (lambda (ls)
     (if (null? ls)
         0
         (+ (length (cdr ls)) 1))))
; Push the labels into the hash table.
(define (hash-labels program)
;   (printf "Hashing labels:~n")
;   (printf "==================================================~n")
   (map (lambda (line) 
          (when (not (null? line))
            (when (or (= 3 (length line))
                      (and (= 2 (length line)) 
                           (not (list? (cadr line)))))
;                (printf "~a: ~s~n" (- (car line) 1) (cadr line))
;                (printf "    ~s~n" (list-ref program (- (car line) 1)))
                (hash-set! l-hash (cadr line) (- (car line) 1 ))
                ))) program)
;   (printf "==================================================~n")
;   (printf "Dumping label table...~n")
;   (map (lambda (el) (printf "~s~n" el))(hash->list l-hash))
)
; This is the main function that gets called.
(define (main arglist)
   (if (or (null? arglist) (not (null? (cdr arglist))))
      ; Case 1. Number of args != 1.
      (usage-exit) 
      ; Case 2. Set sbprogfile = filename from argument
      (let* ((sbprogfile (car arglist))
            ; Set program = The list of commands in the inputfile.
            (program (readlist-from-inputfile sbprogfile))) 
        ; Fetch all the labels that occur in program
        (hash-labels program)
        ; Execute the program.
        (eval-line program 0)
        )))
(for-each
  (lambda (pair)
          (hash-set! n-hash (car pair) (cadr pair)))
  `(      ; This hash table translates SB functions to our functions.
      (print ,sb_print)
      (dim   ,sb_dim)
      (let   ,sb_let)
      (input ,sb_input)
      (if    (void))
      (goto  (void))))
(main (vector->list (current-command-line-arguments)))

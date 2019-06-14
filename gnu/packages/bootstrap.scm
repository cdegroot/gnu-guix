;;; GNU Guix --- Functional package management for GNU
;;; Copyright © 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2019 Ludovic Courtès <ludo@gnu.org>
;;; Copyright © 2014, 2015, 2018 Mark H Weaver <mhw@netris.org>
;;; Copyright © 2017 Efraim Flashner <efraim@flashner.co.il>
;;; Copyright © 2018 Jan (janneke) Nieuwenhuizen <janneke@gnu.org>
;;;
;;; This file is part of GNU Guix.
;;;
;;; GNU Guix is free software; you can redistribute it and/or modify it
;;; under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 3 of the License, or (at
;;; your option) any later version.
;;;
;;; GNU Guix is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with GNU Guix.  If not, see <http://www.gnu.org/licenses/>.

(define-module (gnu packages bootstrap)
  #:use-module (guix licenses)
  #:use-module (gnu packages)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix build-system)
  #:use-module (guix build-system gnu)
  #:use-module (guix build-system trivial)
  #:use-module ((guix store)
                #:select (run-with-store add-to-store add-text-to-store))
  #:use-module ((guix derivations)
                #:select (derivation derivation->output-path))
  #:use-module ((guix utils) #:select (gnu-triplet->nix-system))
  #:use-module (guix memoization)
  #:use-module (guix i18n)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-26)
  #:use-module (srfi srfi-34)
  #:use-module (srfi srfi-35)
  #:use-module (ice-9 match)
  #:export (bootstrap-origin
            package-with-bootstrap-guile
            glibc-dynamic-linker

            bootstrap-guile-origin

            %bootstrap-guile
            %bootstrap-coreutils&co
            %bootstrap-linux-libre-headers
            %bootstrap-binutils
            %bootstrap-gcc
            %bootstrap-glibc
            %bootstrap-inputs
            %bootstrap-mescc-tools
            %bootstrap-mes

            %bootstrap-inputs-for-tests))

;;; Commentary:
;;;
;;; Pre-built packages that are used to bootstrap the
;;; distribution--i.e., to build all the core packages from scratch.
;;;
;;; Code:



;;;
;;; The bootstrap executables: 'bash', 'mkdir', 'tar', 'xz'.  They allow us to
;;; extract the very first tarball.
;;;

(define %bootstrap-executables
  ;; List of bootstrap executables and their recursive hashes (as per 'guix
  ;; hash -r'), taking their executable bit into account.
  `(("aarch64-linux"
     ("bash"
      ,(base32 "13aqhqb8nydlwq1ah9974q0iadx1pb95v13wzzyf7vgv6nasrwzr"))
     ("mkdir"
      ,(base32 "1pxhdp7ldwavmm71xbh9wc197cb2nr66acjn26yjx3732cixh9ws"))
     ("tar"
      ,(base32 "1j51gv08sfg277yxj73xd564wjq3f8xwd6s9rbcg8v9gms47m4cx"))
     ("xz"
      ,(base32 "1d779rwsrasphg5g3r37qppcqy3p7ay1jb1y83w7x4i3qsc7zjy2")))
    ("armhf-linux"
     ("bash"
      ,(base32 "0s6f1s26g4dsrrkl39zblvwpxmbzi6n9mgqf6vxsqz42gik6bgyn"))
     ("mkdir"
      ,(base32 "1r5rcp35niyxfkrdf00y2ba8ifrq9bi76cr63lwjf2l655j1i5p7"))
     ("tar"
      ,(base32 "0dksx5im3fv8ximz7368bsax9f26nn47ds74298flm5lnvpv9xly"))
     ("xz"
      ,(base32 "1cqqavghjfr0iwxqf61lrssv27wfigysgq2rs4rm1gkmn04yn1k3")))
    ("i686-linux"
     ("bash"
      ,(base32 "0rjaxyzjdllfkf1abczvgaf3cdcc7mmahyvdbkjmjzhgz92pv23g"))
     ("mkdir"
      ,(base32 "133ybmfpkmsnysrzbngwvbysqnsmfi8is8zifs7i7n6n600h4s1w"))
     ("tar"
      ,(base32 "07830bx29ad5i0l1ykj0g0b1jayjdblf01sr3ww9wbnwdbzinqms"))
     ("xz"
      ,(base32 "0i9kxdi17bm5gxfi2xzm0y73p3ii0cqxli1sbljm6rh2fjgyn90k")))
    ("mips64el-linux"
     ("bash"
      ,(base32 "1aw046dhda240k9pb9iaj5aqkm23gkvxa9j82n4k7fk87nbrixw6"))
     ("mkdir"
      ,(base32 "0c9j6qgyw84zxbry3ypifzll13gy8ax71w40kdk1h11jbgla3f5k"))
     ("tar"
      ,(base32 "06gmqdjq3rl8lr47b9fyx4ifnm5x56ymc8lyryp1ax1j2s4y5jb4"))
     ("xz"
      ,(base32 "09j1d69qr0hhhx4k4ih8wp00dfc9y4rp01hfg3vc15yxd0jxabh5")))))

(define (bootstrap-executable-url program system)
  "Return the URL where PROGRAM can be found for SYSTEM."
  (string-append
   "https://git.savannah.gnu.org/cgit/guix.git/plain/gnu/packages/bootstrap/"
   system "/" program
   "?id=44f07d1dc6806e97c4e9ee3e6be883cc59dc666e"))

(define bootstrap-executable
  (mlambda (program system)
    "Return an origin for PROGRAM, a statically-linked bootstrap executable
built for SYSTEM."
    (let ((system (if (string=? system "x86_64-linux")
                      "i686-linux"
                      system)))
      (match (assoc-ref (assoc-ref %bootstrap-executables system)
                        program)
        (#f
         (raise (condition
                 (&message
                  (message
                   (format #f (G_ "could not find bootstrap binary '~a' \
for system '~a'")
                           program system))))))
        ((sha256)
         (origin
           (method url-fetch/executable)
           (uri (bootstrap-executable-url program system))
           (file-name program)
           (sha256 sha256)))))))


;;;
;;; Helper procedures.
;;;

(define (bootstrap-origin source)
  "Return a variant of SOURCE, an <origin> instance, whose method uses
%BOOTSTRAP-GUILE to do its job."
  (define (boot fetch)
    (lambda* (url hash-algo hash
              #:optional name #:key system)
      (fetch url hash-algo hash name
             #:guile %bootstrap-guile
             #:system system)))

  (define %bootstrap-patch-inputs
    ;; Packages used when an <origin> has a non-empty 'patches' field.
    `(("tar"   ,%bootstrap-coreutils&co)
      ("xz"    ,%bootstrap-coreutils&co)
      ("bzip2" ,%bootstrap-coreutils&co)
      ("gzip"  ,%bootstrap-coreutils&co)
      ("patch" ,%bootstrap-coreutils&co)))

  (let ((orig-method (origin-method source)))
    (origin (inherit source)
      (method (cond ((eq? orig-method url-fetch)
                     (boot url-fetch))
                    (else orig-method)))
      (patch-guile %bootstrap-guile)
      (patch-inputs %bootstrap-patch-inputs)

      ;; Patches can be origins as well, so process them.
      (patches (map (match-lambda
                     ((? origin? patch)
                      (bootstrap-origin patch))
                     (patch patch))
                    (origin-patches source))))))

(define* (package-from-tarball name source program-to-test description
                               #:key snippet)
  "Return a package that correspond to the extraction of SOURCE.
PROGRAM-TO-TEST is #f or a string: the program to run after extraction of
SOURCE to check whether everything is alright.  If SNIPPET is provided, it is
evaluated after extracting SOURCE.  SNIPPET should return true if successful,
or false to signal an error."
  (package
    (name name)
    (version "0")
    (build-system trivial-build-system)
    (arguments
     `(#:guile ,%bootstrap-guile
       #:modules ((guix build utils))
       #:builder
       (begin
         (use-modules (guix build utils))

         (let ((out     (assoc-ref %outputs "out"))
              (tar     (assoc-ref %build-inputs "tar"))
              (xz      (assoc-ref %build-inputs "xz"))
              (tarball (assoc-ref %build-inputs "tarball")))

          (mkdir out)
          (copy-file tarball "binaries.tar.xz")
          (invoke xz "-d" "binaries.tar.xz")
          (let ((builddir (getcwd)))
            (with-directory-excursion out
              (invoke tar "xvf"
                      (string-append builddir "/binaries.tar"))
              ,@(if snippet (list snippet) '())
              (or (not ,program-to-test)
                  (invoke (string-append "bin/" ,program-to-test)
                          "--version"))))))))
    (inputs
     `(("tar" ,(bootstrap-executable "tar" (%current-system)))
       ("xz"  ,(bootstrap-executable "xz" (%current-system)))
       ("tarball" ,(bootstrap-origin (source (%current-system))))))
    (source #f)
    (synopsis description)
    (description description)
    (home-page #f)
    (license gpl3+)))

(define package-with-bootstrap-guile
  (mlambdaq (p)
    "Return a variant of P such that all its origins are fetched with
%BOOTSTRAP-GUILE."
    (define rewritten-input
      (match-lambda
        ((name (? origin? o))
         `(,name ,(bootstrap-origin o)))
        ((name (? package? p) sub-drvs ...)
         `(,name ,(package-with-bootstrap-guile p) ,@sub-drvs))
        (x x)))

    (package (inherit p)
             (source (match (package-source p)
                       ((? origin? o) (bootstrap-origin o))
                       (s s)))
             (inputs (map rewritten-input
                          (package-inputs p)))
             (native-inputs (map rewritten-input
                                 (package-native-inputs p)))
             (propagated-inputs (map rewritten-input
                                     (package-propagated-inputs p)))
             (replacement (and=> (package-replacement p)
                                 package-with-bootstrap-guile)))))

(define* (glibc-dynamic-linker
          #:optional (system (or (and=> (%current-target-system)
                                        gnu-triplet->nix-system)
                                 (%current-system))))
  "Return the name of Glibc's dynamic linker for SYSTEM."
  ;; See the 'SYSDEP_KNOWN_INTERPRETER_NAMES' cpp macro in libc.
  (cond ((string=? system "x86_64-linux") "/lib/ld-linux-x86-64.so.2")
        ((string=? system "i686-linux") "/lib/ld-linux.so.2")
        ((string=? system "armhf-linux") "/lib/ld-linux-armhf.so.3")
        ((string=? system "mips64el-linux") "/lib/ld.so.1")
        ((string=? system "i586-gnu") "/lib/ld.so.1")
        ((string=? system "i686-gnu") "/lib/ld.so.1")
        ((string=? system "aarch64-linux") "/lib/ld-linux-aarch64.so.1")
        ((string=? system "powerpc-linux") "/lib/ld.so.1")
        ((string=? system "powerpc64le-linux") "/lib/ld64.so.2")
        ((string=? system "alpha-linux") "/lib/ld-linux.so.2")
        ((string=? system "s390x-linux") "/lib/ld64.so.1")
        ((string=? system "riscv64-linux") "/lib/ld-linux-riscv64-lp64d.so.1")

        ;; XXX: This one is used bare-bones, without a libc, so add a case
        ;; here just so we can keep going.
        ((string=? system "arm-elf") "no-ld.so")
        ((string=? system "arm-eabi") "no-ld.so")
        ((string=? system "xtensa-elf") "no-ld.so")
        ((string=? system "avr") "no-ld.so")
        ((string=? system "propeller-elf") "no-ld.so")
        ((string=? system "i686-mingw") "no-ld.so")
        ((string=? system "vc4-elf") "no-ld.so")

        (else (error "dynamic linker name not known for this system"
                     system))))


;;;
;;; Bootstrap packages.
;;;

(define %bootstrap-base-urls
  ;; This is where the initial binaries come from.
  '("https://alpha.gnu.org/gnu/guix/bootstrap"
    "http://alpha.gnu.org/gnu/guix/bootstrap"
    "ftp://alpha.gnu.org/gnu/guix/bootstrap"
    "http://www.fdn.fr/~lcourtes/software/guix/packages"
    "http://flashner.co.il/guix/bootstrap"))

(define (bootstrap-guile-url-path system)
  "Return the URI for FILE."
  (string-append "/" system
                 (match system
                   ("aarch64-linux"
                    "/20170217/guile-2.0.14.tar.xz")
                   ("armhf-linux"
                    "/20150101/guile-2.0.11.tar.xz")
                   (_
                    "/20131110/guile-2.0.9.tar.xz"))))

(define (bootstrap-guile-hash system)
  "Return the SHA256 hash of the Guile bootstrap tarball for SYSTEM."
  (match system
    ("x86_64-linux"
     (base32 "1w2p5zyrglzzniqgvyn1b55vprfzhgk8vzbzkkbdgl5248si0yq3"))
    ("i686-linux"
     (base32 "0im800m30abgh7msh331pcbjvb4n02smz5cfzf1srv0kpx3csmxp"))
    ("mips64el-linux"
     (base32 "0fzp93lvi0hn54acc0fpvhc7bvl0yc853k62l958cihk03q80ilr"))
    ("armhf-linux"
     (base32 "1mi3brl7l58aww34rawhvja84xc7l1b4hmwdmc36fp9q9mfx0lg5"))
    ("aarch64-linux"
     (base32 "1giy2aprjmn5fp9c4s9r125fljw4wv6ixy5739i5bffw4jgr0f9r"))))

(define (bootstrap-guile-origin system)
  "Return an <origin> object for the Guile tarball of SYSTEM."
  (origin
    (method url-fetch)
    (uri (map (cute string-append <> (bootstrap-guile-url-path system))
              %bootstrap-base-urls))
    (sha256 (bootstrap-guile-hash system))))

(define (download-bootstrap-guile store system)
  "Return a derivation that downloads the bootstrap Guile tarball for SYSTEM."
  (let* ((path (bootstrap-guile-url-path system))
         (base (basename path))
         (urls (map (cut string-append <> path) %bootstrap-base-urls)))
    (run-with-store store
      (url-fetch urls 'sha256 (bootstrap-guile-hash system)
                 #:system system))))

(define* (raw-build store name inputs
                    #:key outputs system search-paths
                    #:allow-other-keys)
  (define (->store file)
    (run-with-store store
      (origin->derivation (bootstrap-executable file system)
                          system)))

  (let* ((tar   (->store "tar"))
         (xz    (->store "xz"))
         (mkdir (->store "mkdir"))
         (bash  (->store "bash"))
         (guile (download-bootstrap-guile store system))
         ;; The following code, run by the bootstrap guile after it is
         ;; unpacked, creates a wrapper for itself to set its load path.
         ;; This replaces the previous non-portable method based on
         ;; reading the /proc/self/exe symlink.
         (make-guile-wrapper
          '(begin
             (use-modules (ice-9 match))
             (match (command-line)
               ((_ out bash)
                (let ((bin-dir    (string-append out "/bin"))
                      (guile      (string-append out "/bin/guile"))
                      (guile-real (string-append out "/bin/.guile-real"))
                      ;; We must avoid using a bare dollar sign in this code,
                      ;; because it would be interpreted by the shell.
                      (dollar     (string (integer->char 36))))
                  (chmod bin-dir #o755)
                  (rename-file guile guile-real)
                  (call-with-output-file guile
                    (lambda (p)
                      (format p "\
#!~a
export GUILE_SYSTEM_PATH=~a/share/guile/2.0
export GUILE_SYSTEM_COMPILED_PATH=~a/lib/guile/2.0/ccache
exec -a \"~a0\" ~a \"~a@\"\n"
                              bash out out dollar guile-real dollar)))
                  (chmod guile   #o555)
                  (chmod bin-dir #o555))))))
         (builder
          (add-text-to-store store
                             "build-bootstrap-guile.sh"
                             (format #f "
echo \"unpacking bootstrap Guile to '$out'...\"
~a $out
cd $out
~a -dc < $GUILE_TARBALL | ~a xv

# Use the bootstrap guile to create its own wrapper to set the load path.
GUILE_SYSTEM_PATH=$out/share/guile/2.0 \
GUILE_SYSTEM_COMPILED_PATH=$out/lib/guile/2.0/ccache \
$out/bin/guile -c ~s $out ~a

# Sanity check.
$out/bin/guile --version~%"
                                     (derivation->output-path mkdir)
                                     (derivation->output-path xz)
                                     (derivation->output-path tar)
                                     (format #f "~s" make-guile-wrapper)
                                     (derivation->output-path bash)))))
    (derivation store name
                (derivation->output-path bash) `(,builder)
                #:system system
                #:inputs `((,bash) (,mkdir) (,tar) (,xz)
                           (,builder) (,guile))
                #:env-vars `(("GUILE_TARBALL"
                              . ,(derivation->output-path guile))))))

(define* (make-raw-bag name
                       #:key source inputs native-inputs outputs
                       system target)
  (bag
    (name name)
    (system system)
    (build-inputs inputs)
    (build raw-build)))

(define %bootstrap-guile
  ;; The Guile used to run the build scripts of the initial derivations.
  ;; It is just unpacked from a tarball containing a pre-built binary.
  ;; This is typically built using %GUILE-BOOTSTRAP-TARBALL below.
  ;;
  ;; XXX: Would need libc's `libnss_files2.so' for proper `getaddrinfo'
  ;; support (for /etc/services).
  (let ((raw (build-system
               (name 'raw)
               (description "Raw build system with direct store access")
               (lower make-raw-bag))))
   (package
     (name "guile-bootstrap")
     (version "2.0")
     (source #f)
     (build-system raw)
     (synopsis "Bootstrap Guile")
     (description "Pre-built Guile for bootstrapping purposes.")
     (home-page #f)
     (license lgpl3+))))

(define %bootstrap-coreutils&co
  (package-from-tarball "bootstrap-binaries"
                        (lambda (system)
                          (origin
                           (method url-fetch)
                           (uri (map (cut string-append <> "/" system
                                          (match system
                                            ("armhf-linux"
                                             "/20150101/static-binaries.tar.xz")
                                            ("aarch64-linux"
                                             "/20170217/static-binaries.tar.xz")
                                            (_
                                             "/20131110/static-binaries.tar.xz")))
                                     %bootstrap-base-urls))
                           (sha256
                            (match system
                              ("x86_64-linux"
                               (base32
                                "0c533p9dhczzcsa1117gmfq3pc8w362g4mx84ik36srpr7cx2bg4"))
                              ("i686-linux"
                               (base32
                                "0s5b3jb315n13m1k8095l0a5hfrsz8g0fv1b6riyc5hnxqyphlak"))
                              ("armhf-linux"
                               (base32
                                "0gf0fn2kbpxkjixkmx5f4z6hv6qpmgixl69zgg74dbsfdfj8jdv5"))
                              ("aarch64-linux"
                               (base32
                                "18dfiq6c6xhsdpbidigw6480wh0vdgsxqq3xindq4lpdgqlccpfh"))
                              ("mips64el-linux"
                               (base32
                                "072y4wyfsj1bs80r6vbybbafy8ya4vfy7qj25dklwk97m6g71753"))))))
                        "fgrep"                    ; the program to test
                        "Bootstrap binaries of Coreutils, Awk, etc."
                        #:snippet
                        '(let ((path (list (string-append (getcwd) "/bin"))))
                           (chmod "bin" #o755)
                           (patch-shebang "bin/egrep" path)
                           (patch-shebang "bin/fgrep" path)
                           ;; Starting with grep@2.25 'egrep' and 'fgrep' are shell files
                           ;; that call 'grep'.  If the bootstrap 'egrep' and 'fgrep'
                           ;; are not binaries then patch them to execute 'grep' via its
                           ;; absolute file name instead of searching for it in $PATH.
                           (if (not (elf-file? "bin/egrep"))
                             (substitute* '("bin/egrep" "bin/fgrep")
                               (("^exec grep") (string-append (getcwd) "/bin/grep"))))
                           (chmod "bin" #o555))))

(define-public %bootstrap-linux-libre-headers
  (package-from-tarball
   "linux-libre-headers-bootstrap"
   (lambda (system)
     (origin
       (method url-fetch)
       (uri (map (cute string-append <>
                       "/i686-linux/20181020/"
                       "linux-libre-headers-stripped-4.14.67-i686-linux.tar.xz")
                 %bootstrap-base-urls))
       (sha256
        (base32
         "0sm2z9x4wk45bh6qfs94p0w1d6hsy6dqx9sw38qsqbvxwa1qzk8s"))))
   #f                                   ; no program to test
   "Bootstrap linux-libre-headers"))

(define %bootstrap-binutils
  (package-from-tarball "binutils-bootstrap"
                        (lambda (system)
                          (origin
                           (method url-fetch)
                           (uri (map (cut string-append <> "/" system
                                          (match system
                                            ("armhf-linux"
                                             "/20150101/binutils-2.25.tar.xz")
                                            ("aarch64-linux"
                                             "/20170217/binutils-2.27.tar.xz")
                                            (_
                                             "/20131110/binutils-2.23.2.tar.xz")))
                                     %bootstrap-base-urls))
                           (sha256
                            (match system
                              ("x86_64-linux"
                               (base32
                                "1j5yivz7zkjqfsfmxzrrrffwyayjqyfxgpi89df0w4qziqs2dg20"))
                              ("i686-linux"
                               (base32
                                "14jgwf9gscd7l2pnz610b1zia06dvcm2qyzvni31b8zpgmcai2v9"))
                              ("armhf-linux"
                               (base32
                                "1v7dj6bzn6m36f20gw31l99xaabq4xrhrx3gwqkhhig0mdlmr69q"))
                              ("aarch64-linux"
                               (base32
                                "111s7ilfiby033rczc71797xrmaa3qlv179wdvsaq132pd51xv3n"))
                              ("mips64el-linux"
                               (base32
                                "1x8kkhcxmfyzg1ddpz2pxs6fbdl6412r7x0nzbmi5n7mj8zw2gy7"))))))
                        "ld"                      ; the program to test
                        "Bootstrap binaries of the GNU Binutils"))

(define %bootstrap-glibc
  ;; The initial libc.
  (package
    (name "glibc-bootstrap")
    (version "0")
    (source #f)
    (build-system trivial-build-system)
    (arguments
     `(#:guile ,%bootstrap-guile
       #:modules ((guix build utils))
       #:builder
       (begin
         (use-modules (guix build utils))

         (let ((out     (assoc-ref %outputs "out"))
              (tar     (assoc-ref %build-inputs "tar"))
              (xz      (assoc-ref %build-inputs "xz"))
              (tarball (assoc-ref %build-inputs "tarball")))

          (mkdir out)
          (copy-file tarball "binaries.tar.xz")
          (invoke xz "-d" "binaries.tar.xz")
          (let ((builddir (getcwd)))
            (with-directory-excursion out
              (invoke tar "xvf"
                      (string-append builddir
                                     "/binaries.tar"))
              (chmod "lib" #o755)

              ;; Patch libc.so so it refers to the right path.
              (substitute* "lib/libc.so"
                (("/[^ ]+/lib/(libc|ld)" _ prefix)
                 (string-append out "/lib/" prefix)))

              #t))))))
    (inputs
     `(("tar" ,(bootstrap-executable "tar" (%current-system)))
       ("xz"  ,(bootstrap-executable "xz" (%current-system)))
       ("tarball" ,(bootstrap-origin
                    (origin
                     (method url-fetch)
                     (uri (map (cut string-append <> "/" (%current-system)
                                    (match (%current-system)
                                      ("armhf-linux"
                                       "/20150101/glibc-2.20.tar.xz")
                                      ("aarch64-linux"
                                       "/20170217/glibc-2.25.tar.xz")
                                      (_
                                       "/20131110/glibc-2.18.tar.xz")))
                               %bootstrap-base-urls))
                     (sha256
                      (match (%current-system)
                        ("x86_64-linux"
                         (base32
                          "0jlqrgavvnplj1b083s20jj9iddr4lzfvwybw5xrcis9spbfzk7v"))
                        ("i686-linux"
                         (base32
                          "1hgrccw1zqdc7lvgivwa54d9l3zsim5pqm0dykxg0z522h6gr05w"))
                        ("armhf-linux"
                         (base32
                          "18cmgvpllqfpn6khsmivqib7ys8ymnq0hdzi3qp24prik0ykz8gn"))
                        ("aarch64-linux"
                         (base32
                          "07nx3x8598i2924rjnlrncg6rm61c9bmcczbbcpbx0fb742nvv5c"))
                        ("mips64el-linux"
                         (base32
                          "0k97a3whzx3apsi9n2cbsrr79ad6lh00klxph9hw4fqyp1abkdsg")))))))))
    (synopsis "Bootstrap binaries and headers of the GNU C Library")
    (description synopsis)
    (home-page #f)
    (license lgpl2.1+)))

(define %bootstrap-gcc
  ;; The initial GCC.  Uses binaries from a tarball typically built by
  ;; %GCC-BOOTSTRAP-TARBALL.
  (package
    (name "gcc-bootstrap")
    (version "0")
    (source #f)
    (build-system trivial-build-system)
    (arguments
     `(#:guile ,%bootstrap-guile
       #:modules ((guix build utils))
       #:builder
       (begin
         (use-modules (guix build utils)
                      (ice-9 popen))

         (let ((out     (assoc-ref %outputs "out"))
               (tar     (assoc-ref %build-inputs "tar"))
               (xz      (assoc-ref %build-inputs "xz"))
               (bash    (assoc-ref %build-inputs "bash"))
               (libc    (assoc-ref %build-inputs "libc"))
               (tarball (assoc-ref %build-inputs "tarball")))

           (mkdir out)
           (copy-file tarball "binaries.tar.xz")
           (invoke xz "-d" "binaries.tar.xz")
           (let ((builddir (getcwd))
                 (bindir   (string-append out "/bin")))
             (with-directory-excursion out
               (invoke tar "xvf"
                       (string-append builddir "/binaries.tar")))

             (with-directory-excursion bindir
               (chmod "." #o755)
               (rename-file "gcc" ".gcc-wrapped")
               (call-with-output-file "gcc"
                 (lambda (p)
                   (format p "#!~a
exec ~a/bin/.gcc-wrapped -B~a/lib \
     -Wl,-rpath -Wl,~a/lib \
     -Wl,-dynamic-linker -Wl,~a/~a \"$@\"~%"
                           bash
                           out libc libc libc
                           ,(glibc-dynamic-linker))))

               (chmod "gcc" #o555)
               #t))))))
    (inputs
     `(("tar" ,(bootstrap-executable "tar" (%current-system)))
       ("xz"  ,(bootstrap-executable "xz" (%current-system)))
       ("bash" ,(bootstrap-executable "bash" (%current-system)))
       ("libc" ,%bootstrap-glibc)
       ("tarball" ,(bootstrap-origin
                    (origin
                      (method url-fetch)
                      (uri (map (cut string-append <> "/" (%current-system)
                                     (match (%current-system)
                                       ("armhf-linux"
                                        "/20150101/gcc-4.8.4.tar.xz")
                                       ("aarch64-linux"
                                        "/20170217/gcc-5.4.0.tar.xz")
                                       (_
                                        "/20131110/gcc-4.8.2.tar.xz")))
                                %bootstrap-base-urls))
                      (sha256
                       (match (%current-system)
                         ("x86_64-linux"
                          (base32
                           "17ga4m6195n4fnbzdkmik834znkhs53nkypp6557pl1ps7dgqbls"))
                         ("i686-linux"
                          (base32
                           "150c1arrf2k8vfy6dpxh59vcgs4p1bgiz2av5m19dynpks7rjnyw"))
                         ("armhf-linux"
                          (base32
                           "0ghz825yzp43fxw53kd6afm8nkz16f7dxi9xi40bfwc8x3nbbr8v"))
                         ("aarch64-linux"
                          (base32
                           "1ar3vdzyqbfm0z36kmvazvfswxhcihlacl2dzdjgiq25cqnq9ih1"))
                         ("mips64el-linux"
                          (base32
                           "1m5miqkyng45l745n0sfafdpjkqv9225xf44jqkygwsipj2cv9ks")))))))))
    (native-search-paths
     (list (search-path-specification
            (variable "CPATH")
            (files '("include")))
           (search-path-specification
            (variable "LIBRARY_PATH")
            (files '("lib" "lib64")))))
    (synopsis "Bootstrap binaries of the GNU Compiler Collection")
    (description synopsis)
    (home-page #f)
    (license gpl3+)))

(define %bootstrap-mescc-tools
  ;; The initial MesCC tools.  Uses binaries from a tarball typically built by
  ;; %MESCC-TOOLS-BOOTSTRAP-TARBALL.
  (package
    (name "bootstrap-mescc-tools")
    (version "0.5.2")
    (source #f)
    (build-system trivial-build-system)
    (arguments
     `(#:guile ,%bootstrap-guile
       #:modules ((guix build utils))
       #:builder
       (begin
         (use-modules (guix build utils)
                      (ice-9 popen))
         (let ((out     (assoc-ref %outputs "out"))
               (tar     (assoc-ref %build-inputs "tar"))
               (xz      (assoc-ref %build-inputs "xz"))
               (tarball (assoc-ref %build-inputs "tarball")))

           (mkdir out)
           (copy-file tarball "binaries.tar.xz")
           (invoke xz "-d" "binaries.tar.xz")
           (let ((builddir (getcwd))
                 (bindir   (string-append out "/bin")))
             (with-directory-excursion out
               (invoke tar "xvf"
                       (string-append builddir "/binaries.tar"))))))))
    (inputs
     `(("tar" ,(bootstrap-executable "tar" (%current-system)))
       ("xz"  ,(bootstrap-executable "xz" (%current-system)))
       ("tarball"
        ,(bootstrap-origin
          (origin
            (method url-fetch)
            (uri (map
                  (cute string-append <>
                        "/i686-linux/20181020/"
                        "mescc-tools-static-0.5.2-0.bb062b0-i686-linux.tar.xz")
                  %bootstrap-base-urls))
            (sha256
             (base32
              "11lniw0vg61kmyhvnwkmcnkci9ym6hbmiksiqggd0hkipbq7hvlz")))))))
    (synopsis "Bootstrap binaries of MesCC Tools")
    (description synopsis)
    (home-page #f)
    (supported-systems '("i686-linux" "x86_64-linux"))
    (license gpl3+)))

(define %bootstrap-mes
  ;; The initial Mes.  Uses binaries from a tarball typically built by
  ;; %MES-BOOTSTRAP-TARBALL.
  (package
    (name "bootstrap-mes")
    (version "0")
    (source #f)
    (build-system trivial-build-system)
    (arguments
     `(#:guile ,%bootstrap-guile
       #:modules ((guix build utils))
       #:builder
       (begin
         (use-modules (guix build utils)
                      (ice-9 popen))
         (let ((out     (assoc-ref %outputs "out"))
               (tar     (assoc-ref %build-inputs "tar"))
               (xz      (assoc-ref %build-inputs "xz"))
               (tarball (assoc-ref %build-inputs "tarball")))

           (mkdir out)
           (copy-file tarball "binaries.tar.xz")
           (invoke xz "-d" "binaries.tar.xz")
           (let ((builddir (getcwd))
                 (bindir   (string-append out "/bin")))
             (with-directory-excursion out
               (invoke tar "xvf"
                       (string-append builddir "/binaries.tar"))))))))
    (inputs
     `(("tar" ,(bootstrap-executable "tar" (%current-system)))
       ("xz"  ,(bootstrap-executable "xz" (%current-system)))
       ("tarball"
        ,(bootstrap-origin
          (origin
            (method url-fetch)
            (uri (map
                  (cute string-append <>
                        "/i686-linux/20181020/"
                        "mes-minimal-stripped-0.19-i686-linux.tar.xz")
                  %bootstrap-base-urls))
            (sha256
             (base32
              "0k7kkl68a6xaadv47ij0nr9jm5ca1ffj38n7f2lg80y72wdkwr9h")))))))
    (supported-systems '("i686-linux" "x86_64-linux"))
    (synopsis "Bootstrap binaries of Mes")
    (description synopsis)
    (home-page #f)
    (license gpl3+)))

(define (%bootstrap-inputs)
  ;; The initial, pre-built inputs.  From now on, we can start building our
  ;; own packages.
  `(,@(match (%current-system)
        ((or "i686-linux" "x86_64-linux")
         `(("linux-libre-headers" ,%bootstrap-linux-libre-headers)
           ("bootstrap-mescc-tools" ,%bootstrap-mescc-tools)
           ("mes" ,%bootstrap-mes)))
        (_
         `(("libc" ,%bootstrap-glibc)
           ("gcc" ,%bootstrap-gcc)
           ("binutils" ,%bootstrap-binutils))))
    ("coreutils&co" ,%bootstrap-coreutils&co)

    ;; In gnu-build-system.scm, we rely on the availability of Bash.
    ("bash" ,%bootstrap-coreutils&co)))

(define %bootstrap-inputs-for-tests
  ;; These are bootstrap inputs that are cheap to produce (no compilation
  ;; needed) and that are meant to be used for testing.  (These are those we
  ;; used before the Mes-based reduced bootstrap.)
  `(("libc" ,%bootstrap-glibc)
    ("gcc" ,%bootstrap-gcc)
    ("binutils" ,%bootstrap-binutils)
    ("coreutils&co" ,%bootstrap-coreutils&co)
    ("bash" ,%bootstrap-coreutils&co)))

;;; bootstrap.scm ends here

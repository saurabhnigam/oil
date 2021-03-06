# Demonstrations for users.  Could go in docs.

#### GetValue scope and shopt --unset dynamic_scope

f() {
  echo "sh x=$x"
}

proc p {
  echo "oil x=$x"
}

demo() {
  local x=dynamic
  f
  p

  shopt --unset dynamic_scope
  f
}

x=global
demo
echo x=$x

## STDOUT:
sh x=dynamic
oil x=global
sh x=global
x=global
## END


#### SetValue scope and shopt --unset dynamic_scope
f() {
  x=f
}

proc p {
  x=p
}

demo() {
  local x=stack
  echo x=$x
  echo ---

  f
  echo f x=$x

  x=stack
  p
  echo p x=$x

  shopt --unset dynamic_scope
  x=stack
  f
  echo funset x=$x
}

x=global
demo

echo ---
echo x=$x

## STDOUT:
x=stack
---
f x=f
p x=stack
funset x=stack
---
x=global
## END

#### read scope (setref)
read-x() {
  echo new | read x
}
demo() {
  local x=42
  echo x=$x
  read-x
  echo x=$x
}
demo
echo x=$x

echo ---

shopt --unset dynamic_scope  # should NOT affect read
demo
echo x=$x

## STDOUT:
x=42
x=new
x=
---
x=42
x=new
x=
## END

#### printf -v scope (setref)
set-x() {
  printf -v x "%s" new
}
demo() {
  local x=42
  echo x=$x
  set-x
  echo x=$x
}
demo
echo x=$x

echo ---

shopt --unset dynamic_scope  # should NOT affect read
demo
echo x=$x

## STDOUT:
x=42
x=new
x=
---
x=42
x=new
x=
## END

#### ${undef=a} and shopt --unset dynamic_scope

set-x() {
  : ${x=new}
}
demo() {
  local x
  echo x=$x
  set-x
  echo x=$x
}

demo
echo x=$x

echo ---

# Now this IS affected?
shopt --unset dynamic_scope 
demo
echo x=$x
## STDOUT:
x=
x=new
x=
---
x=
x=
x=
## END

#### declare -p respects it
__g=G
show-vars() {
  local __x=X
  declare -p | grep '__'
  echo status=$?

  echo -
  declare -p __y | grep '__'
  echo status=$?
}

demo() {
  local __y=Y

  show-vars
  echo ---
  shopt --unset dynamic_scope
  show-vars
}

demo

## STDOUT:
declare -- __g=G
declare -- __x=X
declare -- __y=Y
status=0
-
declare -- __y=Y
status=0
---
declare -- __g=G
declare -- __x=X
status=0
-
status=1
## END



#### unset composes because it uses dynamic scope (even in Oil)
shopt -s oil:all

proc unset-two {
  unset $1 
  unset $2
}

demo() {
  local x=X
  local y=Y

  echo "x=$x y=$y"

  unset-two x y

  shopt --unset nounset
  echo "x=$x y=$y"
}

demo
## STDOUT:
x=X y=Y
x= y=
## END


#### SetLocalShopt constructs

f() {
  (( x = 42 ))
}
demo() {
  f
  echo x=$x
}

demo

echo ---

shopt --unset dynamic_scope

unset x

demo

echo --- global
echo x=$x
## STDOUT:
x=42
---
x=
--- global
x=
## END


#### shell assignments 'neutered' inside 'proc'

# They can't mutate globals or anything higher on the stack

proc p {
  g=PROC
  export e=PROC
}

f() {
  g=SH
  export e=SH
}

e=E
g=G
p
echo e=$e g=$g

p
echo e=$e g=$g

f
echo e=$e g=$g

## STDOUT:
e=E g=G
e=E g=G
e=SH g=SH
## END

#### setvar still allows setting globals

proc p {
  setvar new_global = 'p'
  setvar g = 'p'
}

var g = 'G'

p

echo g=$g new_global=$new_global
## STDOUT:
g=p new_global=p
## END

#### setref with :out param

# The name is mangled with : so you can't use it
proc append(:s, suffix) {
  setref s = "$s-$suffix"
}

proc set-it(:s, val) {
  #pp cell __s
  setref s = "foo-$val"
}

proc demo {
  var s = 'abc'
  var t = 'def'
  set-it :s SS
  set-it :t TT

  echo $s
  echo $t
}

demo

## STDOUT:
foo-SS
foo-TT
## END

#### setref without :out param
proc set-it(:s, val) {
  setref val = 'oops'
}

var s = 'abc'
set-it :s SS
echo $s

## status: 1
## STDOUT:
## END

#### setref: syntax without pgen2 using open proc

# This is kind of what we compile to.  Ref params get an extra __ prefix?  then
# that means you can't really READ them either?  I think that's OK.

# At call time, param binding time:
#   If the PARAM has a colon prefix:
#     Assert that the ARG has a colon prefix.  Don't remove it.
#     Set the cell.nameref flag.
#
# At Setref time:
#   Check that it's cell.nameref.
#   Add extra : to lvalue.{Named,Indexed,Keyed} and perform it.
#
# The __ avoids the nameref cycle check.
# And we probably disallow reading from the ref.  That's OK.  The caller can
# pass it in as a regular value!

proc set-it {
  local -n __s=$1  # nameref flag needed with setref
  local val=$2

  # well this part requires pgen2
  setref s = "foo-$val"
}

var s = 'abc'
var t = 'def'
set-it s SS
set-it t TT  # no colon here
echo $s
echo $t

## STDOUT:
foo-SS
foo-TT
## END

#### setref a[i]

# You can do this in bash/mksh.  See nameref!

proc set1(:a, item) {
  setref a[1] = item
}

var a = %(one two three)
var myarray = %(a b c)

set1 :a zzz
set1 :myarray z

shopt --set oil:basic
#write -- @a
write -- @myarray

## STDOUT:
a
z
c
## END

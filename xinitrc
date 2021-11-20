#!/bin/sh
#
# ~/.xinitrc
#
# Executed by startx (run your window manager from here)

userresources=$HOME/.Xresources
usermodmap=$HOME/.Xmodmap
sysresources=/etc/X11/xinit/.Xresources
sysmodmap=/etc/X11/xinit/.Xmodmap

[ -f $sysresources ]    && xrdb -merge $sysresources
[ -f "$userresources" ] && xrdb -merge "$userresources"
[ -f $sysmodmap ]       && xmodmap $sysmodmap
[ -f "$usermodmap" ]    && xmodmap "$usermodmap"

# start some nice programs

if [ -d /etc/X11/xinit/xinitrc.d ] ; then
    for f in /etc/X11/xinit/xinitrc.d/?*.sh ; do
        [ -x "$f" ] && . "$f"
    done
    unset f
fi

exec dbus-launch --sh-syntax --exit-with-session i3 --shmlog-size 0
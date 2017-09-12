############################################################
# koreShield plugin by Revok/iMikeLance
# Este é um merge dos plugins:
# * detectGM
# * pingGMpp
# * broadcastAnalyst
# * playerRecorder
# r2 ~ 04/10/2012 ~ fixed unloading/reloading, added a function similiar to playerRecorder plugin, added chatLog detection logs.
# r1 ~ 02/10/2012 ~ added ping_notWhileQueued config key
# r0 ~ 25/09/2012 ~ merge plugins
#
# TODO:
# * adicionar blacklist de monstros
# * salvar prováveis ID de GMs num arquivo de log.
# * armazenar detecções em uma lista. 
# * No koreShield_ping, checar se o ID detectado está na blacklist, se estiver é resultado do check de pings.
# * Checar se existe um objeto na tela com este ID, se existir NAO É RESULTADO DE koreSHield_ping e devemos kitar imediatamente.
# * [DONE] Caso entre em um mapa onde recentemente foi detectado um GM, desconecte
#
# Copyright (c) 2012-2060 bROShop Development Team
############################################################

package koreShield;

use strict;
use Plugins;
use lib $Plugins::current_plugin_folder;
use Utils qw( existsInList getFormattedDate timeOut makeIP compactArray calcPosition distance);
use Time::HiRes qw(time);
use Log qw( warning message error debug );
use Misc;
use AI;
use Globals;
use I18N qw(bytesToString);
use Commands;
use ActorList;
use RevokUtils::Parsers;

my $pushover_timeout = 0;

sub pushover {
	my ($reason, $message, $priority) = @_;
	return if !timeOut($pushover_timeout, 15);
	my @sound = ('gamelan', 'mechanical', 'alien');
	$pushover_timeout = time;
	my $final_message = $message."\n";
	my $server = $config{master};
	$server =~ s/Brazil - bRO: //;
	$final_message .= $server." - ".$config{username};
	require LWP::UserAgent;
	LWP::UserAgent->new()->post(
	  'https://api.pushover.net/1/messages.json' , [
	  "token" => 'YOUR_PUSHOVER_TOKEN',
	  "user" => 'YOUR_PUSHOVER_USERNAME',
	  "message" => $final_message,
	  "title" => $reason,
	  "priority" => 0,
	  "sound" => $priority == -1 ? 'none' : $sound[$priority],
	  "timestamp" => int(time)
	]);
	return;
}

sub cmdTestNotification {
	my $name = '[GM]bRO'.int(rand(20));
	my $push_title;
	$push_title .= sprintf("%s detectado.", $name) if $name;

	# my $push_msg
	pushover($push_title, sprintf("Mapa %s", 'gef_fild10'), 0);
}


use constant {
	PLUGINNAME				=>	"koreShield",
	BUS_KORESHIELD_MID 			=> 	"koreShield",
	BUS_KORESHIELD_MID_PING 	=> 	"koreShield_ping",
};


# Plugin
Plugins::register(PLUGINNAME, "", \&core_Unload, \&core_Reload);

my $commands_hooks = Commands::register(
	['ks_r', 'change material',			\&cmdKSr],
	['ks_r_on', 'change material',		\&cmdKSr_on],
	['ks_r_off', 'change material',		\&cmdKSr_off],
	['ks_n', 'change material',			\&cmdTestNotification],
);

my $myHooks = Plugins::addHooks(
	['start3',	\&core_start3],
	# core
	['packet/received_character_ID_and_Map',	\&core_mapServerInfo],
	['packet/actor_info',						\&core_actorInfo], #changed from pre_
	#all of these were packet_pre
	['packet/actor_action',						\&core_actorInfo],
	['packet/actor_exists',						\&core_actorInfo],
	['packet/actor_connected',					\&core_actorInfo],
	['packet/actor_spawned',					\&core_actorInfo],
	['packet/actor_died_or_disappeared',		\&core_actorInfo],
	['packet/actor_display',					\&core_actorInfo],
	['packet/actor_movement_interrupted',		\&core_actorInfo],
	['packet/actor_look_at',					\&core_actorInfo],
	['packet/actor_moved',						\&core_actorInfo],
	['packet/item_used',						\&core_actorInfo],
	['packet/actor_status_active',				\&core_actorInfo],
	['packet/unit_levelup',						\&core_actorInfo],
	['packet/stat_info',						\&core_actorInfo],
	['packet/player_equipment',					\&core_actorInfo],
	['packet/GM_req_acc_name',					\&core_actorInfo],
	['packet/deal_request',						\&core_actorInfo],
	['packet/party_invite',						\&core_actorInfo],
	['packet/friend_request',					\&core_actorInfo],	
	['charNameUpdate',							\&core_actorInfo],
	
	['packet_pre/map_loaded',					\&core_mapLogin],
	['packet_pre/map_change',					\&core_mapChange_pre],
	['packet_pre/map_changed',					\&core_mapChange_pre],
	['packet/map_change',						\&core_mapChange_post],
	['packet/map_changed',						\&core_mapChange_post], # used by detectGM and by buscheck to save map:ip
	['postloadfiles',							\&core_overrideConfigKeys],
	['configModify',							\&core_overrideModifiedKey],
	# detectgm
	['packet_pre/item_skill',					\&detectGM_flyOrButterflyWing_tpflag],
	['packet/manner_message',					\&detectGM_manner],
	['packet/GM_silence',						\&detectGM_manner],
	['packet/actor_muted',						\&detectGM_someonesMuted],
	['perfect_hidden_player',       			\&detectGM_perfectHide],
	['packet_skilluse',							\&detectGM_analyseSkillCaster],
	['is_casting',								\&detectGM_analyseSkillCaster],
	['teleport_sent',							\&detectGM_tpFlag_on],
	#['packet/public_chat',					\&detectGM_tpFlag_on],
	['packet/warp_portal_list',					\&detectGM_tpFlag_on], # new!
	['packet/npc_talk',							\&detectGM_addNPCtalkTolerance],
	['packet/npc_talk_continue',				\&detectGM_addNPCtalkTolerance],
	['packet/npc_talk_close',					\&detectGM_addNPCtalkTolerance],
	['packet/npc_talk_responses',				\&detectGM_addNPCtalkTolerance],
	['packet/npc_talk_number',					\&detectGM_addNPCtalkTolerance],
	['packet/npc_talk_text',					\&detectGM_addNPCtalkTolerance],
	['packet/chat_user_leave',					\&detectGM_addNPCtalkTolerance],
	['self_died',								\&detectGM_tpFlag_on],
	['packet/login_error',						\&detectGM_handleLogin],
	['packet/errors',							\&detectGM_handleLogin],
	
	#TODO: ADD SUPPORT FOR packet/actor_status_active, check lullaby deep sleep status
	['packet/character_status',					\&detectGM_forced_status],
	
	
	['packet_pubMsg',							\&detectGM_msg],
	['packet_privMsg',							\&detectGM_msg],
	
	['player_added_to_cache',					\&recorder_cache],
	
	# broadcast
	['packet_pre/local_broadcast',				\&broadcast],
	['packet_pre/system_chat',					\&broadcast],
	#['packet_sysMsg',					\&broadcast],
	['Commands::run/pre',						\&cmdReload],
	['Actor::route::map',						\&foresee_route_danger]
);

my $networkHook = Plugins::addHook('Network::stateChanged',\&bus_isStarted);

my $core_workingFolder = $Plugins::current_plugin_folder;	
my $bus_server;
my ($core_map, $core_mapIP, $core_mapPort);
my %core_databases;
my %core_config;
# pingGMpp variables
my $ping_testMap;
my $ping_idArrayPosition; # should start as 0.
my $ping_nextCheck = time + 0;
my $ping_loopTimeStart;
my @ping_notWhileQueued = split(/\s+/, $core_config{ping_notWhileQueued}); 
my $detectGM_safeTeleport;
my %detectGM_actorTpInfo;

my %ping_dangerousMaps;

my $ignorePasswd = 1;

my @sc_bomb_id_list;

my %server_name_lut = ('200.229.50.3:6900' => 'Thor',
						'200.229.50.36:6900' => 'Odin',
						'200.229.50.20:6900' => 'Asgard',
						'ro.openkore-brasil.com:6900' => 'openkorebrasil',
						);
						
if ($::net) {
 core_start3();
}

sub cmdKSr_on {
	$ignorePasswd = 0;
	message "Password reset WILL TRIGGER \n";
}

sub cmdKSr_off {
	$ignorePasswd = 1;
	message "Password reset wont trigger... \n";
}

sub cmdKSr {
	if ($ignorePasswd == 1) {
		$ignorePasswd = 0;
		message "Turning ignore password off \n";
	} else {
		$ignorePasswd = 1;
		message "Turning ignore password on \n";
	}
}
			
sub core_start3 {
	my $reload = shift;
	if ($reload) {
		undef %core_databases;
		undef %core_config;
	}
	$ping_idArrayPosition = 0;
	my $master = $masterServer = $masterServers{$config{master}};
	message sprintf("Loading %s... \n", 'control-koreshield/koreShield_'.$server_name_lut{$master->{ip}.':'.$master->{port}}.'.txt');
	&RevokUtils::Parsers::parseSectionedFile('control-koreshield/koreShield_'.$server_name_lut{$master->{ip}.':'.$master->{port}}.'.txt', \%core_databases);
	%core_config = &RevokUtils::Parsers::parseConfigArray(\@{$core_databases{CONFIG}});
	message sprintf("GM DB size: %s \n", scalar @{$core_databases{GMIDS}});
}

sub cmdReload {
	my (undef, $args) = @_;
	if ($args->{switch} eq 'reload' && $args->{args} =~ /koreshield|ks|^all$/i) {
		core_start3(1);
	}
}

# BUS handle plugin loaded manually (plugin load/reload inside kore)
# this is used just in case the user reloads the plugin
# this code will be skipped during automatic plugin loading
# if ($::net) {
	# if ($::net->getState() > 1) {
		# $bus_server = $bus->onMessageReceived->add(undef, \&bus_parseMsg);
		# Plugins::delHook($networkHook);
		# undef $networkHook;
	# }
# }

sub foresee_route_danger {
	my ($self, $args) = @_;
	foresee_map_danger($args->{map});
}


sub foresee_map_danger {
	my ($map) = @_;
	if ($ping_dangerousMaps{$map}) {
		my $relog_time = $core_config{ping_relogTime} || 110;# minutes
		my $time = $ping_dangerousMaps{$map} + ($relog_time * 60);
		if ($time > time) {
			error "...dangerous \n";
			my $seed = $core_config{ping_relogTimeSeed} || 70;# minutes
			$seed  = $seed * 60;
			my $relog_time = ($time - time) + int(rand $seed);		
			relog($relog_time);
			return;
		} else {
			message "...expired, removing. \n", 'message';
			delete $ping_dangerousMaps{$map};
		}
	}
	message "...safe! \n", 'success';
	
}

sub detectGM_someonesMuted {
	if (defined $field && $field && !$field->isCity()) {
		error sprintf("Alguém foi mutado fora da cidade! \n"), "koreShield_detect";
		&core_eventsReaction('player_muted');
	}
}

sub detectGM_msg {
	my ($self, $args) = @_;
	if ($args->{pubID} && isIn_Array(unpack("V",$args->{pubID}), \@{$core_databases{GMIDS}}) eq 1) {
		error sprintf("Player de ID blacklisted %s falou em $self! \n", unpack("V",$args->{pubID})), "koreShield_detect";
		&core_eventsReaction($self);
	} elsif ($args->{MsgUser} && (isIn_Array_Regex($args->{MsgUser}, \@{$core_databases{NAMES}}))) {
		error sprintf("Player de nome blacklisted %s falou em $self! \n", $args->{pubMsgUser}), "koreShield_detect";
		&core_eventsReaction($self);
	}
}

sub detectGM_forced_status {
	my (undef, $args) = @_;
	return; # TODO: fix this
	if (($args->{opt1} == 4) && ($args->{ID} eq $accountID)) {
		error sprintf("Status Sono forçado! \n"), "koreShield_detect";
		&core_eventsReaction('forced_status');
	}
}


# we're checking if our client is set to connect to a bus server. if not, warn the user.
# caller: Network::stateChange hook
# params: none
sub bus_isStarted {
	#return if ($::net->getState() == 1);
	if (!$bus) {
		die("Você DEVE iniciar um servidor BUS e configurar cada bot do OpenKore para usá-lo. Abra o arquivo control/sys.txt e configure bus 0 para bus 1. \n\n");
	} elsif (!$bus_server) {
		$bus_server = $bus->onMessageReceived->add(undef, \&bus_parseMsg);
		Plugins::delHook($networkHook);
		undef $networkHook;
	}
}

# receives message from another kore instance and check if we should react
# caller: $bus_server = $bus_server->onMessageReceived->add(undef, \&bus_parseMsg);
# params: undef, undef, bus message (array of vars)
sub bus_parseMsg {
	return if ($core_config{disable} || $core_config{disable_core});
	my (undef, undef, $msg) = @_;
	return if (!$core_map);
	if ($core_mapIP && $core_mapPort && ($msg->{messageID} eq BUS_KORESHIELD_MID_PING)) {
		if ($msg->{args}{mapserver} eq $core_mapIP.$core_mapPort) {
			debug (sprintf("From BUS: %s %s %s %s (%s)\n",
						$msg->{messageID},
						$msg->{args}{player},
						$core_mapIP.$core_mapPort,
						$msg->{args}{time},
						time - $msg->{args}{time}
					), "koreShield_ping");
					
			if (($msg->{args}{time} + (30*$core_config{ping_checkDelay})) < time) {
				error sprintf("Found a bug! %s asked me to wait, but time (%s) is lower than current time...\n", $msg->{args}{player}, $msg->{args}{time});
				#system('msg Revok bug escroto do BUS detectado, sou o '.$char->{name}.'!');
				#quit();
				#return;
			}
					
			$ping_nextCheck = Time::HiRes::time + (30*$core_config{ping_checkDelay}) + rand(20);
			debug (sprintf("%s asked me to wait. Next check in %s seconds \n",
						$msg->{args}{player},
						int($ping_nextCheck - time)
					), "koreShield_ping");
						
			$ping_idArrayPosition = 0;
		}
	} elsif ($msg->{messageID} eq BUS_KORESHIELD_MID) {
		&core_eventsReaction($msg->{args}{danger}, $msg->{args});
	}
}

sub detectGM_analyseSkillCaster {
	return if ($core_config{disable} || $core_config{disable_detect} || !$core_config{detectGM_avoidStrangeSkillsBehaviour});
	my ($caller, $args) = @_;
	
	# 70 = santuario
	# 73 = kyrie
	# 12 = escudo magico
	# 29 = agi
	# 34 = bençao
	# 361 = assumptio
	# 476 = Remoção Total
	# 2304 = Copia explosiva
	my $castername = Actor::get($args->{sourceID});
	debug sprintf("%s %s %s casted a skill \n",
				unpack("V1", $args->{sourceID}),
				$castername->{name},
				$castername->{jobID}
			), "koreShield_detect";
			
	
	
	return if ($core_config{detectGM_notInTown} && $field->isCity());
	return if (unpack("V1", $args->{sourceID}) eq unpack("L1", $accountID)); # won't check if it's our own ID
	
	if ($args->{skillID} == 2304) { # handle sc bomb
		push (@sc_bomb_id_list, unpack("V", $args->{sourceID}));
		debug (sprintf("SC Bomb: adding %s to \@sc_bomb_id_list \n",unpack("V", $args->{sourceID})), "koreShield_detect");
	}
	
	return unless ($castername->{jobID} == 4057); # unsafe
	return if ($castername->{jobID} == 17);
	
	
	my $skillname = $args->{skillID}?sprintf("%s (%s)", (new Skill(idn => $args->{skillID}))->getName, $args->{skillID}):sprintf("Desconhecida (%s)", $args->{skillID});
	
	return if unpack("V", $args->{sourceID}) < 100000;
	
	$messageSender->sendGetPlayerInfo(pack("V", unpack("V1", $args->{sourceID}))); # to be used with pingGMpp [OK]
	
	if ($caller eq 'is_casting') {
		if (isIn_Array(unpack("V1", $args->{sourceID}), \@{$core_databases{GMIDS}})) {
			error sprintf("Player de ID %s da blacklist está castando %s! Desconectando... \n", unpack("V1", $args->{sourceID}), $skillname), "koreShield_detect";
			&core_eventsReaction('blacklisted_used_skill');
			return;
		} elsif (($args->{skillID} == 73) && (unpack("V1", $args->{targetID}) eq unpack("L1", $accountID))) { # kyrie eleison
			if ($castername->{name} =~ /^Unknown \#\d+/ || !$castername->{name}) {
				error sprintf("Player desconhecido %s (%s) está buffando você com %s! Desconectando...\n", $castername->{name}, unpack("V", $args->{sourceID}), $skillname), "koreShield_detect";
				&core_eventsReaction('unknown_buffed_me');
				return;
			}
		} elsif ((unpack("V1", $args->{targetID}) eq unpack("L1", $accountID)) && ($castername->{name} =~ /^Unknown \#\d+/ || !$castername->{name}))  {
			error sprintf("Player desconhecido %s (%s) está castando %s em você ! Desconectando...\n", $castername->{name}, unpack("V", $args->{sourceID}), $skillname), "koreShield_detect";
			&core_eventsReaction('unknown_used_skill_me');
			return;
		
		}
		
		if (AI::action eq "attack") {
			my $monsterID = AI::args->{ID};
			if (($monsterID eq $args->{targetID}) && AI::args->{dmgFromYou_last} && $args->{sourceID}) {
			#warning "lol ".$monstersList->getByID($args->{sourceID})."\n" if $monstersList->getByID($args->{sourceID});
				if ((grep {$_ eq $args->{skillID}} (73, 2051)) && !($monstersList->getByID($args->{sourceID}))) { # do not detect 28 (Heal) here
					error sprintf("Player %s (%s) está castando %s no seu monstro! Desconectando...\n", $castername->{name}, unpack("V", $args->{sourceID}), $skillname), "koreShield_detect";
					&core_eventsReaction('slaving_monster');
				}
			}
		}
	} elsif ($caller eq 'packet_skilluse') {
		if ($args->{sourceID} && (isIn_Array(unpack("V1", $args->{sourceID}), \@{$core_databases{GMIDS}}))) {
			error sprintf("Player de ID %s da blacklist usou %s! Desconectando... \n", unpack("V1", $args->{sourceID}), $skillname), "koreShield_detect";
			&core_eventsReaction('blacklisted_used_skill');
			return;
		} elsif ($castername =~ /^(NPC|Player)? ?\[?GM\]?.*/) {
			error sprintf("%s com [GM] no nick usou %s! Desconetando... \n", $castername->{name}, $skillname), "koreShield_detect";
			&core_eventsReaction('gm_used_skill');
			return;
		}
		
		if (unpack("V1", $args->{targetID}) eq unpack("L1", $accountID)) { # target skills
			if ($args->{skillID} == 29 || $args->{skillID} == 34 || $args->{skillID} == 361) { # alguns buffs menos kyrie
				if ($castername =~ /^Unknown \#\d+/ || !$castername->{name}) {
					error sprintf("Player desconhecido %s (%s) buffou você com %s! Desconectando...\n", $castername->{name}, unpack("V", $args->{sourceID}), $skillname), "koreShield_detect";
					&core_eventsReaction('unknown_buffed_me');
					return;
				}
			} elsif ($args->{skillID} == 476) { # remoção total
					error sprintf("Player desconhecido %s (%s) te deu %s! Desconectando...\n", $castername->{name}, unpack("V", $args->{sourceID}), $skillname), "koreShield_detect";
					&core_eventsReaction('fullstripped');
					return; 
			} elsif (($castername->{name} =~ /^Unknown \#\d{6,16}/ || !$castername->{name}) && (unpack("V", $args->{sourceID}) >= 100000)) {
				error sprintf("Player desconhecido %s (%s) utilizou %s em você ! Desconectando...\n", $castername->{name}, unpack("V", $args->{sourceID}), $skillname), "koreShield_detect";
				&core_eventsReaction('unknown_used_skill_me');
				return;
			}
		} else { # ground skills
			if ($args->{skillID} == 70) { # santuário
				my %skill_cast_pos;
				($skill_cast_pos{x}, $skill_cast_pos{y}) = ($args->{x}, $args->{y});
				if (&detectGM_analyseSkillCaster_isInsideSanctuary(\%skill_cast_pos)) {
					&core_eventsReaction('monster_sanctuary');
				}
			} elsif ($args->{skillID} == 12) { # escudo mágico
				my %skill_cast_pos;
				($skill_cast_pos{x}, $skill_cast_pos{y}) = ($args->{x}, $args->{y});
				if (&detectGM_analyseSkillCaster_isInsideSW(\%skill_cast_pos)) {
					&core_eventsReaction('monster_sw');
				}
			} elsif ($args->{skillID} == 27) { # warp portal
				if ($config{master} =~ /(Thor|Revok)/) {
					error sprintf("Player %s (%s) utilizou um portal em servidor nao permitido ! Desconectando...\n", $castername->{name}, unpack("V", $args->{sourceID})), "koreShield_detect";
					&core_eventsReaction('alien_skill');
				}
			}
		
		}
		
		if (AI::action eq "attack") {
			my $monsterID = AI::args->{ID};
			if (($monsterID eq $args->{targetID}) && AI::args->{dmgFromYou_last} && $args->{sourceID}) {
				my $lol;
				grep { $lol .= unpack("V", $_)." " } ($monsterID, $args->{targetID});
				warning "$lol\n";
				if (
						((grep {$_ eq $args->{skillID}} (73, 2051)) || (($args->{skillID} eq 28) && !$args->{damage}))
						&& !($monstersList->getByID($args->{sourceID}))
					) {
					error sprintf("Player %s (%s) usou %s no seu monstro! Desconectando...\n", $castername->{name}, unpack("V", $args->{sourceID}), $skillname), "koreShield_detect";
					&core_eventsReaction('slaving_monster');
				}
			}
		}
	}
}

sub detectGM_analyseSkillCaster_isInsideSW {
	return if ($core_config{disable} || $core_config{disable_detect});
	my $skill_cast_pos = shift;
	foreach my $monster (@{$monstersList->getItems()}) {
		my $mx = $monster->{pos_to}{x};
		my $my = $monster->{pos_to}{y};
		if (($skill_cast_pos->{x} == $mx) && ($skill_cast_pos->{y} == $my) && (Actor::distance($monster) <= $core_config{detectGM_monsterMaxDist})) {
			error sprintf("SW casted inside monster (%s blocks away)\n", Actor::distance($monster)), "koreShield_detect";
			return 1;
		}
	}
}


sub detectGM_analyseSkillCaster_isInsideSanctuary {
	return if ($core_config{disable} || $core_config{disable_detect});
	my $skill_cast_pos = shift;
	foreach my $monster (@{$monstersList->getItems()}) {
		my $mx = $monster->{pos_to}{x};
		my $my = $monster->{pos_to}{y};
		if ( ($skill_cast_pos->{x} >= ($mx - 3) && $skill_cast_pos->{x} <= ($mx + 3)) && ($skill_cast_pos->{y} >= ($my - 3) && $skill_cast_pos->{y} <= ($my + 3)) && (Actor::distance($monster) <= $core_config{detectGM_monsterMaxDist}) ) {
			error sprintf("Sanctuary casted inside monster (%s blocks away) \n", Actor::distance($monster)), "koreShield_detect";
			return 1;
		}
	}
}

sub detectGM_addNPCtalkTolerance {
	return if ($core_config{disable} || $core_config{disable_detect});
	$detectGM_actorTpInfo{npctalk} = time + $core_config{detectGM_toleranceAfterNPCtalk};
	debug (sprintf("Adicionando tempo de espera (%s s)após falar com NPC. \n", $core_config{detectGM_toleranceAfterNPCtalk}), "koreShield_detect");
}

sub detectGM_flyOrButterflyWing_tpflag {
	return if ($core_config{disable} || $core_config{disable_detect});
	my ($caller, $args) = @_;
	if ($args->{skillID} == 26) {
		$detectGM_safeTeleport = 1;
		debug (sprintf("\$detectGM_safeTeleport changed to %s \n", $detectGM_safeTeleport), "koreShield_detect");
	}
}

sub detectGM_manner {
	error("Chat bloqueado, estamos sendo banidos, desconectando...\n"), "koreShield_detect";
	&core_eventsReaction('chat_blocked');
	pushover('Chat bloqueado', 'Chat bloqueado, estamos sendo banidos, desconectando...', 1);
}

sub detectGM_perfectHide {
	return if ($core_config{disable} || $core_config{disable_detect} || !$core_config{detectGM_avoidPerfectHidden});
	my ($caller, $args) = @_;
	
	# check sc_bomb_id_list
	for (my $i = $#sc_bomb_id_list; $i > -1; $i--) {
		if (unpack("V", $args->{actor}->{ID}) eq $sc_bomb_id_list[$i]) {
			debug (sprintf("Removing %s from \@sc_bomb_id_list and ignoring perfecthide \n", unpack("V", $args->{actor}->{ID})), 'koreShield_detect');
			splice (@sc_bomb_id_list, $i, 1);
			return;
		}
	}
	
	my $player = Actor::get($args->{actor}->{ID});	
	return if ($player && $player->{jobID} == 4079); # 4079 => 'Shadow Chaser',
	
	my $msg;
	$msg .= sprintf("Um GM em perfect hide (%s) foi detectado! Desconectando...\n", $args->{actor}->{name});
	$msg .= "=================== UM GM FOI DETECTADO ==================\n";
	$msg .= sprintf("Called by hook %s\n", $caller);
	$msg .= sprintf("Time: %s\n", getFormattedDate(time));
	$msg .= sprintf("Map: %s\n", $field?$field->baseName:"Unknown");
	$msg .= sprintf("ID: %s\n", unpack("V", $args->{actor}->{ID})) if $args->{actor}->{ID};
	$msg .= sprintf("Level: %s\n", unpack("V", $args->{actor}->{level})) if $args->{actor}->{level};
	$msg .= sprintf("Nome: %s\n", unpack("Z24", $args->{actor}->{name})) if $args->{actor}->{name};
	$msg .= sprintf("Nome da party: %s\n", unpack("Z24", $args->{actor}->{partyName})) if $args->{actor}->{partyName};
	$msg .= sprintf("Nome da guild: %s\n", unpack("Z24", $args->{actor}->{guildName})) if $args->{actor}->{guildName};
	$msg .= sprintf("Título na guild: %s\n", unpack("Z24", $args->{actor}->{guildTitle})) if $args->{actor}->{guildTitle};
	$msg .= "==========================================================\n";
	error ($msg, "koreShield_detect");
	&core_eventsReaction('perfect_hidden');
}

sub broadcast {
	return if ($core_config{disable} || $core_config{disable_broadcast});
	my ($caller, $args) = @_;
	# received msg in bytes
	my $message = bytesToString($args->{message});
	chomp($message); # remove newline
	$message =~ s/\000//g; # remove null charachters
	#$message =~ s/^(tool[0-9a-fA-F]{6})//g; # remove those annoying toolDDDDDD from bRO (and maybe some other server?)
	#$message =~ s/^ssss//g; # remove those annoying ssss from bRO (and maybe some other server?)
	#$message =~ s/^ +//g; $message =~ s/ +$//g; # remove whitespace in the beginning and the end of $message
	if ($message =~ /\Q$char->{'name'}/i ) {
		error sprintf("Received a broadcast with our nickname !\n".
						"Broadcast: %s \n", $message), "koreShield_broadcast";
		chatLog("koreShield.broadcast", "$message\n");
		kLog($message."\n", 'broadcast_nickname.log');
		&core_eventsReaction('broadcast_nickname');
		pushover('Broadcast - Nickname', $message, 1);
	} elsif (isIn_Array_Regex($message, \@{$core_databases{BROADCASTWHITELIST}}, 1)) {
		debug (sprintf("Allowed broadcast: %s\n", $message), "koreShield_broadcast");
		kLog($message."\n", 'broadcast_whitelist.log');
	} elsif (isIn_Array_Regex($message, \@{$core_databases{BROADCASTBLACKLIST}}, 1)) {
		error sprintf("Match: %s \n", isIn_Array_Regex($message, \@{$core_databases{BROADCASTBLACKLIST}}, 1)), "koreShield_broadcast";
		error sprintf("Received a blacklisted broadcast.\nForbidden broadcast: %s \n", $message), "koreShield_broadcast";
		chatLog("koreShield.broadcast", "$message\n");
		kLog($message."\n", 'broadcast_blacklist.log');
		&core_eventsReaction('broadcast_blacklisted');
		pushover('Broadcast - Blacklist', $message, 1);
	} else {
		error sprintf("Received a broadcast thats not inside whitelist or blacklist.\nForbidden broadcast: %s \n", $message), "koreShield_broadcast";
		chatLog("koreShield.broadcast", "$message\n");
		kLog($message."\n", 'broadcast_unknown.log');
		&core_eventsReaction('broadcast_unknown');
		pushover('Broadcast - Unknown', $message, 0);
	}
}

sub detectGM_checkAllowedMap {
	my $map = shift;
	if (
		existsInList($core_config{detectGM_forbiddenMaps}, $map)
	)
	{
		error sprintf("The current map (%s) is not on the list of allowed maps or is forbidden.\n", $map), "koreShield_detect";
		&core_eventsReaction('forbidden_map');
	}
}

sub detectGM_isPortalNear {
	for (my $i = 0; $i < @portalsID; $i++) {
		next if $portalsID[$i] eq "";
		my $portal = $portals{$portalsID[$i]};
		message sprintf("I'm at %s %s Portal at %s %s Distance(%s) \n",
							$char->{pos_to}{x},
							$char->{pos_to}{y},
							$portal->{pos}{x},
							$portal->{pos}{y},
							&distance(calcPosition($char), calcPosition($portal))
						), "koreShield_detect";
							
		return 1 if (distance(calcPosition($char), calcPosition($portal)) <= 15);
	}
	return 0;
}

sub core_calcDist {
	# calculate distance between char and provided coordinates
	my ($a, $b) = @_;
	return sqrt(($char->{pos_to}{x} - $a)**2 + ($char->{pos_to}{y} - $b)**2); # pythagorean
}

sub detectGM_tpFlag_on {
	return if ($core_config{disable} || $core_config{disable_detect});
	return if $detectGM_safeTeleport;
	my ($self, $args) = @_;
	$detectGM_safeTeleport = 1;
	debug (sprintf("\$detectGM_safeTeleport changed to %s \n", $detectGM_safeTeleport), "koreShield_detect");
}

sub detectGM_tpFlag_off {
	return if ($core_config{disable} || $core_config{disable_detect});
	return unless $detectGM_safeTeleport;
	$detectGM_safeTeleport = 0;
	debug (sprintf("\$detectGM_safeTeleport changed to %s \n", $detectGM_safeTeleport), "koreShield_detect");
}

sub detectGM_handleLogin {
	 # 4		conta bloqueada - mais comum em privates
	 # 6		banida por tempo - mais comum em oficiais, bRO
	 # 15	GM te deu kick
	 # 101	geralmente banida por muitas conexões
	 # 102	o mesmo de 101, porém incomum em oficiais
	my (undef, $args) = @_;
	if ($args->{date} && $args->{type} == 6) {
		my ($date, $hour) = split(' ', $args->{date});
	}
	#$args->{type} == 4 bug do bRO
	if ($args->{type} == 6 || $args->{type} == 15 || $args->{type} == 101 || $args->{type} == 102) {
		error("Conta bloqueada ou GM nos derrubou, desconectando... \n"), "koreShield_detect";
		#return;
		&core_eventsReaction('banned');
		pushover("Sendo banido", '', 2);
	} elsif ($args->{type} == Network::Receive::REFUSE_INVALID_PASSWD) {
		$config{ignoreInvalidLogin} = 1;
		&core_eventsReaction('passwd_reset') unless $ignorePasswd;
		pushover("Reset de senha", '', 1) unless $ignorePasswd;
	}	
}

sub core_overrideConfigKeys {
	foreach (keys %core_config) {
		next if !exists($config{'koreShield_'.$_});
		message sprintf("Overriding %s with %s\n", $_, "koreShield_".$_), "koreShield";
		$core_config{$_} = $config{'koreShield_'.$_};
	}
	
}

sub core_overrideModifiedKey {
	my (undef, $args) = @_;
	if ($args->{key} =~ /^koreShield_/) {
		my $modified_key = $args->{key};
		$modified_key =~ s/^koreShield_//;
		warning sprintf("Overriding %s with %s \n", $args->{key}, $modified_key), "koreShield";
		$core_config{$modified_key} = $args->{value};
	}
}

sub recorder_cache {
	return; # desativa isso :D
	my ($caller, $args) = @_;
	return if $field->isCity();
	# TODO: make unique entries
	my $targetName = $args->{name};
	#my $selfName = $char->name(); # my own name
	my $file = "$Settings::logs_folder/players_$servers[$config{'server'}]{'name'}_$config{username}.txt";
	debug (sprintf("Player Exists: %s (%s) \n", $targetName, unpack("V1", $args->{ID})), "koreShield_recorder");
	open FILE, ">>:utf8", $file;
	my $time=localtime time;
	print FILE swrite("[$time] " . $field->baseName . " ".unpack("V1", $args->{ID})." \@<<<<<<<<<<<<<<<<<<<<<<<< \@<<< \@<<<<<<<<<< \@<<<<<<<<<<<<<<<<", [$args->{name},$args->{lv}, $jobs_lut{$args->{jobID}}, $args->{guild}]);
	#print FILE $args->{name}\t$args->{lv}\t".$jobs_lut{$args->{jobID}}."\t$args->{guild}\n";
	close FILE;

}

sub core_actorInfo {
	return if ($core_config{disable} || $core_config{disable_core});
	my ($caller, $args) = @_;
	
	return unless $packetParser->changeToInGameState();
	
	#'a4 v8 V v6 a4 a2 v2 C2 a6 C2 v'
	#[qw(ID walk_speed opt1 opt2 option type hair_style weapon lowhead tick shield tophead midhead hair_color clothes_color head_dir guildID emblemID manner opt3 stance sex coords unknown1 unknown2 lv)]], #walking
	my $ID;
	$ID = unpack("V1", $args->{ID}) if $args->{ID};
	$ID = unpack("V1", $args->{sourceID}) if $args->{sourceID};
	$ID = $args->{player}{nameID} if $args->{player}{nameID};
	
	return if !$ID;	
	return if ($ID < 100000);
	return if ($ID eq unpack("L1", $accountID)); # won't check if it's our own ID	
	
	my $player;
	# get stored actor info
	if ($ID) {
		$player = $playersList->getByID(pack("V1", $ID)) if $playersList;
	}	
	if (isIn_Array($ID, \@{$core_databases{WHITELISTIDS}}) eq 1) {
		warning "Ignoring whitelisted ID $ID \n";
		return;
	}
	# set name 
	my $name = $player?$player->name:unpack("Z24", $args->{name});
	my $detect_reason;
	if (isIn_Array($ID, \@{$core_databases{GMIDS}}) eq 1) {
		$detect_reason = 'ID na blacklist';
	} elsif ($name && (isIn_Array_Regex(unpack("Z24", $name), \@{$core_databases{NAMES}}))) {
		$detect_reason = 'Nome na blacklist';
	} elsif (defined $player && $player->{guild} && (isIn_Array_Regex($player->{guild}{name}, \@{$core_databases{GUILD}}))) {
		$detect_reason = 'Guild na blacklist';
	} elsif (defined $player && defined $player->{headgear}{top} && $player->{headgear}{top} && (isIn_Array($player->{headgear}{top}, \@{$core_databases{EQUIPS}}))) {
		$detect_reason = sprintf("Hat top (%s) na blacklist", $player->{headgear}{top});
	} elsif (defined $player && defined $player->{headgear}{mid} && $player->{headgear}{mid} && (isIn_Array($player->{headgear}{mid}, \@{$core_databases{EQUIPS}}))) {
		$detect_reason = 'Hat mid na blacklist';
	} elsif (defined $player && defined $player->{headgear}{low} && $player->{headgear}{low} && (isIn_Array($player->{headgear}{low}, \@{$core_databases{EQUIPS}}))) {
		$detect_reason = 'Hat low na blacklist';
	} elsif (defined $player && defined $player->{weapon} && $player->{weapon} && (isIn_Array($player->{weapon}, \@{$core_databases{EQUIPS}}))) {
		$detect_reason = 'Arma na blacklist';
	} elsif (defined $player && defined $player->{shield} && $player->{shield} && (isIn_Array($player->{shield}, \@{$core_databases{EQUIPS}}))) {
		$detect_reason = sprintf("Escudo (%s) na blacklist", $player->{shield});
	} elsif (defined $player && defined $player->{party} && (isIn_Array_Regex($player->{party}{name}, \@{$core_databases{PARTY}}))) {
		$detect_reason = 'Party na blacklist';
	} elsif (defined $player && defined $player->{guild} && (isIn_Array_Regex($player->{guild}{title}, \@{$core_databases{GUILDTITLE}}))) {
		$detect_reason = 'Guild title na blacklist';
	}
	if ($detect_reason) {
		$ping_idArrayPosition = 0;
		
		my $msg;
		$msg .= "=================== UM GM FOI DETECTADO ==================\n";
		$msg .= sprintf("Called by hook %s\n", $caller);
		$msg .= sprintf("MOTIVO: %s\n", $detect_reason);
		$msg .= sprintf("User: %s\n", $config{username});
		$msg .= sprintf("Time: %s\n", getFormattedDate(time));
		$msg .= sprintf("Map: %s Zone: %s\n", $field?$field->baseName:"Unknown", ($core_mapIP && $core_mapPort)?$core_mapIP.':'.$core_mapPort:"Unknown");
		$msg .= sprintf("ID: %s\n", $ID);
		$msg .= sprintf("Level: %s\n", unpack("V", $args->{level})) if $args->{level};
		$msg .= sprintf("Nome: %s\n", $name) if $name;
		$msg .= sprintf("Nome da party: %s\n", unpack("Z24", $args->{partyName})) if defined $args->{partyName};
		$msg .= sprintf("Nome da guild: %s\n", unpack("Z24", $args->{guildName})) if defined $args->{guildName};
		$msg .= sprintf("Arma: %s\n", itemName({nameID => $player->{weapon}})) if defined $player->{weapon};
		$msg .= sprintf("Escudo: %s\n", itemName({nameID => $player->{shield}})) if defined $player->{shield};
		if (defined $player->{headgear}) {
			$msg .= sprintf("Hat top: %s (%s)\n", headgearName($player->{headgear}{top}), $player->{headgear}{top});
			$msg .= sprintf("Hat mid: %s (%s)\n", headgearName($player->{headgear}{mid}), $player->{headgear}{mid});
			$msg .= sprintf("Hat low: %s (%s)\n", headgearName($player->{headgear}{low}), $player->{headgear}{low});
		}
		$msg .= sprintf("Título na guild: %s\n", unpack("Z24", $args->{guildTitle})) if $args->{guildTitle};
		$msg .= sprintf("Vel. de Movimento: %s\n", $player->{walk_speed}) if defined $player->{walk_speed};
		$msg .= "==========================================================\n";

		
		
		error ($msg, "koreShield_detect");
		
		kLog($msg, 'detect_log.log');
		
		chatLog("koreShield.ping", "GM Detectado! ID: $ID Nome: ".unpack("Z24", $args->{name})." \n");
		
		foreach my $action_item (@ping_notWhileQueued) {
			if (existsInList($action_item, AI::action())) {
				error sprintf("We won't disconnect because of action: %s \n", $action_item), "koreShield_detect";
				return;
			}
		}
		#warning Data::Dumper::Dumper($player);
		if (($caller eq "packet/actor_info") && !$player->{actorType}) {
			return if ($field && $field->baseName eq 'prontera'); # workaround
			&core_eventsReaction('actor_found_normal', undef, 1);

			my $push_title;
			$push_title .= sprintf("%s detectado.", $name) if $name;

			# my $push_msg
			pushover($push_title, sprintf("Mapa %s", ($field?$field->baseName:"Unknown")), -1);
		} else {
			&core_eventsReaction('actor_found');
			my $push_msg;
			$push_msg .= sprintf("Map: %s\n", $field?$field->baseName:"Unknown", ($core_mapIP && $core_mapPort)?$core_mapIP.':'.$core_mapPort:"Unknown");
			$push_msg .= sprintf("Nome: %s\n", $name) if $name;
			pushover("GM - $detect_reason", $push_msg, 0);
		}
		
			
	} else {
		my $msg;
		$msg .= "=================== INFO DE DEBUG ==================\n";
		$msg .= sprintf("Called by hook %s\n", $caller);
		$msg .= sprintf("Time: %s\n", getFormattedDate(time));
		$msg .= sprintf("ID: %s\n", $ID);
		$msg .= sprintf("Level: %s\n", unpack("V", $args->{level})) if $args->{level};
		$msg .= sprintf("Nome: %s\n", $name) if $name;
		$msg .= sprintf("Nome da party: %s\n", unpack("Z24", $args->{partyName})) if defined $args->{partyName};
		$msg .= sprintf("Nome da guild: %s\n", unpack("Z24", $args->{guildName})) if defined $args->{guildName};
		$msg .= sprintf("Arma: %s\n", itemName({nameID => $player->{weapon}})) if defined $player->{weapon};
		$msg .= sprintf("Escudo: %s\n", itemName({nameID => $player->{shield}})) if defined $player->{shield};
		if (defined $player->{headgear}) {
			$msg .= sprintf("Hat top: %s (%s)\n", headgearName($player->{headgear}{top}), $player->{headgear}{top});
			$msg .= sprintf("Hat mid: %s (%s)\n", headgearName($player->{headgear}{mid}), $player->{headgear}{mid});
			$msg .= sprintf("Hat low: %s (%s)\n", headgearName($player->{headgear}{low}), $player->{headgear}{low});
		}
		$msg .= sprintf("Título na guild: %s\n", unpack("Z24", $args->{guildTitle})) if $args->{guildTitle};
		$msg .= sprintf("Vel. de Movimento: %s\n", $player->{walk_speed}) if defined $player->{walk_speed};
		$msg .= "==========================================================\n";
		debug ($msg, "koreShield_detect");
	}
}


sub kLog {
	my ($msg, $file) = @_;
	my $filename = $file;
	$filename = $servers[$config{'server'}]{'name'}.'_'.$file;
	if (open (my $log_file_fh, '>>', 'logs-koreshield/'.$filename)) {
		print $log_file_fh $msg;
		close $log_file_fh;
	} else {
		error 'Cant open : logs-koreshield/'.$filename."\n";
	}
}

##
# updatePlayerNameCache(player)
# player: a player actor object.
*Network::Receive::updatePlayerNameCache =
*Misc::updatePlayerNameCache = sub {
	my ($player) = @_;
	
	return if (!$config{cachePlayerNames});

	# First, cleanup the cache. Remove entries that are too old.
	# Default life time: 15 minutes
	my $changed = 1;
	for (my $i = 0; $i < @playerNameCacheIDs; $i++) {
		my $ID = $playerNameCacheIDs[$i];
		if (timeOut($playerNameCache{$ID}{time}, $config{cachePlayerNames_duration})) {
			delete $playerNameCacheIDs[$i];
			delete $playerNameCache{$ID};
			$changed = 1;
		}
	}
	compactArray(\@playerNameCacheIDs) if ($changed);

	# Resize the cache if it's still too large.
	# Default cache size: 100
	while (@playerNameCacheIDs > $config{cachePlayerNames_maxSize}) {
		my $ID = shift @playerNameCacheIDs;
		delete $playerNameCache{$ID};
	}

	# Add this player name to the cache.
	my $ID = $player->{ID};
	if (!$playerNameCache{$ID}) {
	# We'll only get here if this players is new
	
		push @playerNameCacheIDs, $ID;
		my %entry = (
			ID => $player->{ID},
			name => $player->{name},
			guild => $player->{guild},
			time => time,
			lv => $player->{lv},
			jobID => $player->{jobID},
			object_type => Scalar::Util::blessed($player)
		);
		$playerNameCache{$ID} = \%entry;
		Plugins::callHook("player_added_to_cache", \%entry);
	}
};

sub core_mapLogin {
	my ($caller, $args) = @_;
	return if ($core_config{disable} || $core_config{disable_detect});
	if ($masterServer->{serverType} =~ /^kRO_/) {
		&detectGM_tpFlag_on();
	}
}


sub core_mapChange_pre {
	my ($caller, $args) = @_;
	return if ($core_config{disable} || $core_config{disable_detect});
	($detectGM_actorTpInfo{map}, $detectGM_actorTpInfo{pos}{x}, $detectGM_actorTpInfo{pos}{y}) =
			($core_map, $char->{pos_to}{x}, $char->{pos_to}{y});
	
	debug (sprintf("Before TP: %s and %s and %s \n", $detectGM_actorTpInfo{map}, $detectGM_actorTpInfo{pos}{x}, $detectGM_actorTpInfo{pos}{y}), "koreShield_detect");
	
	if ($core_config{detectGM_teleportCheck_ignorePortal}) {
		if (&detectGM_isPortalNear()) {
			$detectGM_safeTeleport = 1;
		}
	}
		
	if (!existsInList('NPC', AI::action()) && !$detectGM_safeTeleport && time > $detectGM_actorTpInfo{npctalk} && !$ai_v{npc_talk}{talk}) {
		error("Teleporte não autorizado, desconectando...\n", "koreShield_detect");
		&core_eventsReaction('forced_teleport');
	}
	
	($core_map) = unpack("Z16", $args->{map}) =~ /([\s\S]*)\./; # cut off .gat
}

sub core_mapChange_post {
	my ($caller, $args) = @_;
	($core_map) = unpack("Z16", $args->{map}) =~ /([\s\S]*)\./; # cut off .gat
	
	debug ("Saved core_map\n", "koreShield_detect");
	$core_mapIP = makeIP($args->{IP}) if $args->{IP};
	$core_mapPort = $args->{port} if $args->{port};
	
	return if ($core_config{disable} || $core_config{disable_detect});
	
	debug (sprintf("Before TP: %s and %s and %s \n",
					$core_map,
					$char->{pos_to}{x},
					$char->{pos_to}{y}), "koreShield_detect");
					
	if ( !$detectGM_safeTeleport && ($core_map eq $detectGM_actorTpInfo{map}) && ( $char->{pos_to}{x} eq $detectGM_actorTpInfo{pos}{x}) && ( $char->{pos_to}{y} eq $detectGM_actorTpInfo{pos}{y} ) ) {
		error("Teleportado para a mesma célula, desconectando...\n", "koreShield_detect");
		&core_eventsReaction('forced_teleport_same_cell');
	} elsif (!existsInList('NPC', AI::action()) && !$detectGM_safeTeleport && time > $detectGM_actorTpInfo{npctalk} && !$ai_v{npc_talk}{talk}) {
		error("Teleporte não autorizado, desconectando...", "koreShield_detect");
		&core_eventsReaction('forced_teleport');
	}
	
	&detectGM_tpFlag_off(); # safe to teleport
	foresee_map_danger($core_map);
	detectGM_checkAllowedMap($core_map);

}

sub core_mapServerInfo {
	my (undef, $args) = @_;
	($core_map) = unpack("Z16", $args->{mapName}) =~ /([\s\S]*)\./; # cut off .gat
	debug ("Saved core_map\n", "koreShield_detect");
	$core_mapIP = makeIP($args->{mapIP});
	$core_mapPort = $args->{mapPort};
	foresee_map_danger($core_map);
	detectGM_checkAllowedMap($core_map);
}

sub core_Unload {
	error("Unloading plugin...", "koreShield");
	$bus->onMessageReceived->remove($bus_server) if $bus_server;
	core_SafeUnload();
	undef $bus_server;
	undef $core_map;
	undef $core_mapIP;
	undef $core_mapPort;
	
}

sub core_Reload {
	warning("Reloading plugin...", "koreShield");
	core_SafeUnload();
}

sub core_SafeUnload {
	Plugins::delHooks($myHooks);
	Plugins::delHook($networkHook) if $networkHook;
	Commands::unregister($commands_hooks);
	undef $commands_hooks;
	undef $myHooks;
	undef $networkHook;
	undef $core_workingFolder;
	#undef $bus_server;
	#undef $core_map;
	#undef $core_mapIP;
	#undef $core_mapPort;
	undef %core_databases;
	undef %core_config;
	undef $ping_testMap;
	undef $ping_idArrayPosition;
	undef $ping_nextCheck;
	undef $ping_loopTimeStart;
	undef @ping_notWhileQueued;
	undef $detectGM_safeTeleport;
	undef %detectGM_actorTpInfo;;
	undef %ping_dangerousMaps;
}

sub core_eventsReaction {
	my ($danger, $bus_args, $ifound) = @_;
	if ($bus_args) {
		debug (sprintf("From BUS:\n %s \n %s \n %s \n %s \n %s \n",
						$bus_args->{mapserver},
						$bus_args->{map},
						$bus_args->{player},
						$bus_args->{global},
						$bus_args->{danger}), "koreShield");

						
						
		return if ($config{master} ne $bus_args->{server});

		#message "someone was harmed - koreShield";
		if ($bus_args->{map}) {
			warning "adding map ".$bus_args->{map}." to dangerous list \n";
			$ping_dangerousMaps{$bus_args->{map}} = time;
		}

		if ($bus_args->{mapserver}) {
			return if ($core_config{ignore_detected_ping} || (($core_mapIP.$core_mapPort ne $bus_args->{mapserver}) && !$core_config{promiscuous_mode} && !$core_config{ping_global_halftime}));
			warning sprintf("%s detected an GM in this mapserver !\n", $bus_args->{player}), "koreShield";
		} elsif ($bus_args->{map}) {
			return if ((!$core_map || ($core_map ne $bus_args->{map})) && !$core_config{promiscuous_mode});
			warning sprintf("%s was harmed in this map!\n", $bus_args->{player}), "koreShield";
		} elsif ($bus_args->{global}) {
			warning sprintf("%s has been banned or teleported !\n", $bus_args->{player}), "koreShield";
		}
		
		warning sprintf("Reason: %s !\n", $bus_args->{danger}), "koreShield";
	} else {
		my %args;
		$args{player} = $char->name if $char;
		if ($danger eq 'actor_found_normal') {
			$args{mapserver} = $core_mapIP.$core_mapPort;
		} elsif ($danger eq 'banned' || $danger eq 'forbidden_map') {
			$args{global} = 1
		} else {
			$args{map} = $core_map;
		}
		
		warning "adding map ".$core_map."to dangerous list \n";
		$ping_dangerousMaps{$core_map} = time;
		
		$args{server} = $config{master};
		$args{map} = $core_map;
		$args{danger} = $danger;
		$bus->send(BUS_KORESHIELD_MID, \%args);
		error("Sent notification to other bots.", "koreShield");
		error sprintf("Reason: %s !\n", $danger), "koreShield";
	}
	chatLog("koreShield.core", "Danger: $danger \n");
	#warning "THIS SHIT WORKS";
	if(grep {$_ eq $danger} ('actor_found', 'banned', 'alien_skill', 'blacklisted_used_skill', 'broadcast_blacklisted',
		'broadcast_nickname', 'chat_blocked', 'forced_teleport', 'forced_teleport_same_cell', 'fullstripped', 'actor_disguised',
		'forced_status', 'gm_used_skill', 'monster_sanctuary', 'monster_sw', 'packet_pubMsg', 'packet_privMsg',
		'forbidden_map', 'perfect_hidden', 'player_muted', 'slaving_monster', 'unknown_buffed_me', 'unknown_used_skill_me',
		'passwd_reset'
		)) 
	{
			if (!$core_config{testMode}) {
				relog(999999999); # infinite?
				offlineMode();
			} else {
				Commands::run("c detected $danger");
			}
	} elsif ($danger eq 'actor_found_normal') {
		#relog(900+int(rand 600)); # 15~25min
		# my $relog_time = 90;# minutes
		# my $seed = 50;# minutes
		my $relog_time = $core_config{ping_relogTime} || 110;# minutes
		my $seed = $core_config{ping_relogTimeSeed} || 70;# minutes
		
		if ($bus_args->{mapserver} && ($core_mapIP.$core_mapPort ne $bus_args->{mapserver}) && $core_config{ping_global_halftime}) {
			warning "Using halftime \n";
			$relog_time = $relog_time * $core_config{ping_global_halftime};
			$seed = $seed * $core_config{ping_global_halftime};
		}
		
		$relog_time = $relog_time * 60;
		$seed  = $seed * 60;
		if (!$core_config{testMode}) {
			return if $shopstarted;
			$relog_time += int(rand $seed) if (!$ifound);
			relog($relog_time);
		} else {
			Commands::run("c detected $danger");
		}
	} elsif ($danger eq 'broadcast_unknown') {
		if (!$core_config{testMode}) {
			relog(1800000000); # 5h
		} else {
			Commands::run("c detected $danger");
		}
	}

}

sub T {
	return sprintf @_;
}

1;
# i luv u mom
# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# Copyright (C) 2019-2023 Rother OSS GmbH, https://otobo.de/
# --
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
# --

package Kernel::System::Web::InterfaceMigrateFromOTRS;

use strict;
use warnings;
use v5.24;
use namespace::autoclean;
use utf8;

# core modules

# CPAN modules

# OTOBO modules
use Kernel::Language qw(Translatable);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::Log',
    'Kernel::System::Main',
    'Kernel::System::Web::Request',
    'Kernel::System::Web::Response',
);

=head1 NAME

Kernel::System::Web::InterfaceMigrateFromOTRS - the migration web interface

=head1 SYNOPSIS

    use Kernel::System::Web::InterfaceMigrateFromOTRS;

    # a Plack request handler
    my $App = sub {
        my $Env = shift;

        my $Interface = Kernel::System::Web::InterfaceMigrateFromOTRS->new(
            # Debug => 1
            PSGIEnv    => $Env,
        );

        # generate content (actually headers are generated as a side effect)
        my $Content = $Interface->Content();

        # assuming all went well and HTML was generated
        return [
            '200',
            [ 'Content-Type' => 'text/html' ],
            $Content
        ];
    };

=head1 DESCRIPTION

This module generates the HTTP response for F<migration.pl>.
This class is meant to be used within a Plack request handler.
See F<bin/psgi-bin/otobo.psgi> for the real live usage.

=head1 PUBLIC INTERFACE

=head2 new()

create the web interface object for F<migration.pl>.

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # start with an empty hash for the new object
    my $Self = bless {}, $Type;

    # set debug level
    $Self->{Debug} = $Param{Debug} || 0;

    # register object params
    $Kernel::OM->ObjectParamAdd(
        'Kernel::System::Log' => {
            LogPrefix => $Kernel::OM->Get('Kernel::Config')->Get('CGILogPrefix') || 'MigrateFromOTRS',
        },
        'Kernel::System::Web::Request' => {
            PSGIEnv => $Param{PSGIEnv} || 0,
        },
    );

    # debug info
    if ( $Self->{Debug} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'debug',
            Message  => 'Global handle started...',
        );
    }

    return $Self;
}

=head2 Content()

execute the object.
Set headers in Kernels::System::Web::Request singleton as side effect.

    my $Content = $Interface->Content();
=cut

sub Content {
    my $Self = shift;

    # get common framework params
    my %Param;
    {
        my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');

        $Param{Action}     = $ParamObject->GetParam( Param => 'Action' )     || 'MigrateFromOTRS';
        $Param{Subaction}  = $ParamObject->GetParam( Param => 'Subaction' )  || '';
        $Param{NextScreen} = $ParamObject->GetParam( Param => 'NextScreen' ) || '';
    }

    $Kernel::OM->ObjectParamAdd(
        'Kernel::Output::HTML::Layout' => {
            %Param,
        },
    );

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # check secure mode
    if ( $Kernel::OM->Get('Kernel::Config')->Get('SecureMode') ) {
        return join '',
            $LayoutObject->Header(),
            $LayoutObject->Error(
                Message => Translatable('SecureMode active!'),
                Comment => Translatable(
                    'If you want to re-run migration.pl, then disable the SecureMode in the SysConfig.'
                ),
            ),
            $LayoutObject->Footer();
    }

    # run modules if a version value exists
    if ( $Kernel::OM->Get('Kernel::System::Main')->Require("Kernel::Modules::$Param{Action}") ) {

        # create $GenericObject
        my $GenericObject = ( 'Kernel::Modules::' . $Param{Action} )->new(
            %Param,
            Debug => $Self->{Debug},
        );

        # output filters are not applied for this interface
        return $GenericObject->Run();
    }

    # return an error screen as the fallback
    return join '',
        $LayoutObject->Header(),
        $LayoutObject->Error(
            Message => $LayoutObject->{LanguageObject}->Translate( 'Action "%s" not found!', $Param{Action} ),
            Comment => Translatable('Please contact the administrator.'),
        ),
        $LayoutObject->Footer();
}

=head2 Response()

Generate a PSGI Response object from the content generated by C<Content()>.

    my $Response = $Interface->Response();

=cut

sub Response {
    my ($Self) = @_;

    # Note that no layout object must be created before calling Content().
    # This is because Content() might want to set object params before the initial creations.
    # A notable example is the SetCookies parameter.
    my $Content = $Self->Content();

    # The HTTP headers of the OTOBO web response object already have been set up.
    # Enhance it with the HTTP status code and the content.
    return $Kernel::OM->Get('Kernel::System::Web::Response')->Finalize( Content => $Content );
}

1;
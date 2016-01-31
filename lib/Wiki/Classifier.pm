package Wiki::Classifier;

# ABSTRACT: Given a model or training data, predict the classification for a wiki page.

=head1 Synopsis

# Build and save a model based on two directories of training data.
# parallelized with 10 processes.
Wiki::Classifier->new(
    training_directories => [ 'training_data/positive', 'training_data/negative' ],
    num_procs => 10,
    save_model => 'models/disease_classifier.model',
    )->run;

# Using a pre-built model, predict the classification of a new wiki page.
Wiki::Classifier->new(
    model => <some Algorithm::NaiveBayes object, or a path a saved one>,
    predict_files => [ <paths to files to test> ],
);

=cut

use Moose;
use Moose::Util::TypeConstraints;
use Algorithm::NaiveBayes;
use HTML::TreeBuilder;
use File::Find::Rule;
use Data::Dumper;
use URI::URL;
use Parallel::Loops;

with qw(
    MooseX::Getopt::Usage
    MooseX::Getopt::Usage::Role::Man
    MooseX::Log::Log4perl
);

has 'predict_files' => (
    is => 'rw',
    isa => 'ArrayRef[Str]',
    predicate => 'has_predict_files',
    documentation => 'Paths to files to classify. The model is used to predict the category for each file.',
);

has 'predictions' => (
    is => 'rw',
    traits => ['NoGetopt'],
    isa => 'ArrayRef',
    lazy => 1,
    builder => '_build_predictions',
    documentation => 'Hash of predictions for each file.',
);

sub _build_predictions {
    my ( $self ) = @_;

    my @predictions;

    foreach my $file_path ( @{$self->predict_files} ) {

        my $html = HTML::TreeBuilder->new_from_file( $file_path )->elementify;
        # extract the title of the page
        my ( $title_html )= $html->look_down('id', 'firstHeading');

        my $title = 'N/A';
        if ( $title_html ) {
            $title = $title_html->as_text;
        }

        my $scores = $self->model->predict( attributes => $self->parse_file( $file_path ) );

        # extract the diseaseDB links
        my @disease_links = $html->look_down('href', qr/diseasesdatabase/ );

        my $prediction = {
            title => $title,
            path => $file_path,
            diseaseDB_links => [ map { $_->attr( 'href' ) } @disease_links ],
        };

        foreach my $label ( keys %{$scores} ) {
            $prediction->{"score_$label"} = $scores->{$label};
        }

        push @predictions, $prediction;

    }

    return \@predictions;
}

has 'num_procs' => (
    is => 'rw',
    isa => 'Int',
    predicate => 'has_num_procs',
    documentation => 'Maximum number of processes to fork for parallelizing the parsing of the training files.',
);

has 'forker' => (
    is => 'rw',
    isa => 'Parallel::Loops',
    builder => '_build_forker',
    lazy => 1,
    handles => {
        'fork' => 'foreach',
    },
    documentation => 'Parallel loop object for parallelizing parsing of training data.',
);

sub _build_forker {
    my ( $self ) = @_;
    my $pl = Parallel::Loops->new($self->num_procs);
    return $pl;
}

subtype 'NBModel',
    as 'Algorithm::NaiveBayes';

coerce 'NBModel',
    from 'Str',
    via { Algorithm::NaiveBayes->new->restore_state( $_ ); }
;

MooseX::Getopt::OptionTypeMap->add_option_type_to_map(
    'NBModel', '=s',
);

has 'model' => (
    is => 'rw',
    isa => 'NBModel',
    lazy => 1,
    coerce => 1,
    builder => '_build_model',
    documentation => 'Naive Bayes model for classifying wiki pages. Can be built from "training_data" or by passing in a saved model.',
);

sub _build_model {
    my ( $self ) = @_;

    # first parse the training data
    $self->training_data;

    $self->log->info( 'Training model.' );

    my $model = Algorithm::NaiveBayes->new;

    foreach my $label ( keys %{$self->training_data} ) {
        map { $model->add_instance( attributes => $_, label => $label ) } @{$self->training_data->{$label} };
    }

    $model->train;

    $model->do_purge;

    $self->log->info( 'Done training model.' );

    if ( $self->has_save_model ) {
        $self->log->info( 'Saving model state to: ' . $self->save_model );
        $model->save_state( $self->save_model );
    }

    return $model;
}

has 'save_model' => (
    is => 'rw',
    isa => 'Str',
    predicate => 'has_save_model',
    documentation => 'Filepath to save model state to after training.',
);

has 'training_directories' => (
    is => 'rw',
    isa => 'ArrayRef[Str]',
    documentation => 'Directory of training files for building the model. Each directory represents a "category" or "label" in the model. ',
);

has 'min_word_length' => (
    is => 'rw',
    isa => 'Int',
    default => 4,
    documentation => 'Minimum word length for words to add to the model. ',
);

has 'training_data' => (
    is => 'rw',
    isa => 'HashRef',
    lazy => 1,
    builder => '_build_training_data',
    documentation => '',
);

sub _build_training_data {
    my ( $self ) = @_;

    $self->log->info( 'Building training data.' );
    my %labels;

    foreach my $dir ( @{$self->training_directories} ) {
        my $label = $dir;
        # remove everything up to the last dir name in the path
        $label =~ s/^.*\///;
        $labels{ $label } = $self->parse_training_dir( $dir );
    }

    $self->log->info( 'Done building training data.' );

    return \%labels;
}

=method parse_training_dir

Given a directory, parses all the files inside using the parse_file function.
Forks multiple processes if num_procs is specified.
Returns an arrayref of parsed files.

=cut

sub parse_training_dir {
    my ( $self, $dir ) = @_;

    # get a list of file paths to parse
    my @files = File::Find::Rule->new->file->maxdepth(1)->in($dir);

    $self->log->info( 'Parsing ' . scalar @files . " files for training directory: $dir" );

    my @parsed_files;
    if ( $self->has_num_procs && $self->num_procs > 1 ) {
        $self->forker->share( \@parsed_files );
        $self->fork( \@files, sub { push \@parsed_files, $self->parse_file( $_ ); } );
    } else {
        foreach my $file ( @files ) {
            push \@parsed_files, $self->parse_file( $file );
        }
    }

    $self->log->info( 'Done parsing training directory.' );

    return \@parsed_files;
}

=method parse_file

Given a wiki html file, builds an html tree and then parses the content, links, headers,
and titles out of the file using the "parse_*" methods.
Returns a hash of word counts for all the parsed data in the file.

=cut

sub parse_file {
    my ( $self, $file_path ) = @_;

    #$self->log->debug( "Parsing file: $file_path" );

    my $html = HTML::TreeBuilder->new_from_file( $file_path )->elementify;

    my @parsed_words;

    # first parse out the actual text content
    push @parsed_words, @{$self->parse_content( $html )};

    # next parse out any links
    push @parsed_words, @{$self->parse_links( $html )};

    # next parse out any headers
    push @parsed_words, @{$self->parse_headers( $html )};

    # next parse out any titles
    push @parsed_words, @{$self->parse_titles( $html )};

    # count up the words
    my %word_counts;
    foreach my $word ( @parsed_words ) {
        next if length($word) < $self->min_word_length;
        $word_counts{ $word } += 1;
    }

    return \%word_counts;
}

=method parse_content

Given an html tree, parses the content in the "mw-content-text" element.
Returns an arrayref of individual parsed words.

=cut

sub parse_content {
    my ( $self, $html ) = @_;

    my @content_words;

    my ( $content ) = $html->look_down( 'id', 'mw-content-text' );
    return \@content_words unless $content;

    my $content_text = $content->format;

    # strip anything except for spaces and word (a-zA-Z_) characters
    $content_text =~ s/[^\s\w]//g;

    # substitute tabs and multiple spaces for a single space
    $content_text =~ s/[\s|\t]+/ /g;

    # lowercase and split the prepped text on spaces
    @content_words = split( ' ', lc($content_text) );

    return \@content_words;
}

=method parse_links

Given an html tree, parses the href tags. Pulls the "authority" or base out of external links
and also parses relative wiki links.
Returns an array of parsed "words".

=cut

sub parse_links {
    my ( $self, $html ) = @_;

    my @link_words;

    my @links = $html->look_down( 'href', qr/.*/ );

    foreach my $link ( @links ) {
        my $url = $link->attr('href');

        # try to extract the "authority" out of the url
        my $authority = URI::URL->new( $url )->authority;
        if ( $authority ) {
            # strip leading www.
            # this is so that www.google.com and google.com will match.
            $authority =~ s/^www\.//;
            push @link_words, $authority;
        };

        # capture relative wikipedia link
        if ( $url =~ /^\/wiki\//i ) {

            push @link_words, lc($url);
        }

    }

    return \@link_words;
}

=method parse_headers

0Given an html tree, parses the "head" class tags, such as "mw-headline".
Each header is treated as a single "word."
Returns and arrayref of parsed "words."

=cut

sub parse_headers {
    my ( $self, $html ) = @_;

    my @header_words;

    my @headers = $html->look_down( 'class', qr/head/ );

    foreach my $header ( @headers ) {
        my $header_word = $header->as_text;
        # replace spaces with "_"
        # want to treat the entire header as a single "word"
        $header_word =~ s/\s+/_/g;
        # lowercase everything
        push @header_words, lc($header_word);
    }

    return \@header_words;
}

=method parse_titles

Given an html tree, parses the "title" elements and extracts words from those fields.
Returns and arrayref of parsed "words."

=cut

sub parse_titles {
    my ( $self, $html ) = @_;

    my @title_words;

    my @titles = $html->look_down( 'title', qr/.*/ );

    foreach my $title ( @titles ) {
        my $title_word = $title->as_text;
        # cleanup extra spaces
        $title_word =~ s/\s+/ /g;
        # lowercase everything
        push @title_words, lc($title_word);
    }

    return \@title_words;
}

=method run

Helper function for commandline use.
Builds the model and then classifies the input files and logs predictions

=cut

sub run {
    my ( $self ) = @_;
    $self->model;

    $Data::Dumper::Sortkeys = 1;
    if ( $self->has_predict_files ) {
        $self->log->info( Dumper( $self->predictions ) );
    }

    return 1;
}

1;

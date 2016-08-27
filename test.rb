gem 'minitest'
require 'minitest/autorun'
require 'fileutils'
require 'open3'
require 'tmpdir'
require 'tempfile'

KEEPDIR = File.expand_path('../bin/keepdir', __FILE__)

def subdirs
   [ 'a/b/c',
     'a/d',
     'a/e',
     'a/.git',
     'a/b/.git/f'
   ]
end

def touch(path)
   open(path, 'w') {|w| nil }
end

def keepdir(*args)
   Dir.chdir($tmpdir) {
      _stdin, stdout, _stderr, th = Open3.popen3(KEEPDIR, *args)
      th.value
      stdout.read
   }
end

def keepdir_status(*args)
   Dir.chdir($tmpdir) {
      _stdin, _stdout, _stderr, th = Open3.popen3(KEEPDIR, *args)
      th.value
   }
end

def yes_keepdir(yes, *args)
   Dir.chdir($tmpdir) {
      Open3.pipeline_r(['yes', yes], [KEEPDIR, *args]) {|out, ths|
         out.read
      }
   }
end

def eof_keepdir(*args)
   Dir.chdir($tmpdir) {
      stdin, stdout, _stderr, th = Open3.popen3(KEEPDIR, *args)
      stdin.close_write
      stdout.read
   }
end

describe 'Keepdir' do
   def testpath(path)
      File.join($tmpdir, path)
   end

   before do
      $tmpdir = File.realpath(Dir.mktmpdir)
      subdirs.each do |dir|
         FileUtils.mkdir_p testpath(dir)
      end
   end

   after do
      FileUtils.rm_rf($tmpdir)
   end

   describe '--help' do
      it 'exits successfully' do
         keepdir_status('--help').must_equal 0
      end
   end

   describe '--update' do
      it 'must create keepfiles for empty directory' do
         keepdir
         File.ftype(testpath('a/b/c/.keep')).must_equal 'file'
         File.ftype(testpath('a/d/.keep')).must_equal 'file'
         File.ftype(testpath('a/e/.keep')).must_equal 'file'
      end

      it 'must print created files in realpath (this may change)' do
         keepdir.must_equal <<EOF
create #{testpath('a/b/c/.keep')}
create #{testpath('a/d/.keep')}
create #{testpath('a/e/.keep')}
EOF
      end

      it 'must suppress output with -q' do
         keepdir('-q').lines.must_be :empty?
      end

      it 'must delete a keepfile if it exists in an non-empty directory' do
         touch(testpath('a/b/c/.aaa'))
         touch(testpath('a/b/c/.keep'))
         keepdir
         File.exist?(testpath('a/b/c/.keep')).must_equal false
         File.exist?(testpath('a/d/.keep')).must_equal true
         File.exist?(testpath('a/e/.keep')).must_equal true
      end

      it 'must not create keepfiles for non-empty directories' do
         keepdir
         File.exist?(testpath('a/b/.keep')).must_equal false
         File.exist?(testpath('a/.keep')).must_equal false
         File.exist?(testpath('.keep')).must_equal false
      end

      it 'must prune at .git' do
         keepdir
         File.exist?(testpath('a/.git/.keep')).must_equal false
         File.exist?(testpath('a/b/.git/f/.keep')).must_equal false
      end

      it 'must update keepfiles' do
         keepdir
         File.ftype(testpath('a/b/c/.keep')).must_equal 'file'
         File.ftype(testpath('a/d/.keep')).must_equal 'file'
         File.ftype(testpath('a/e/.keep')).must_equal 'file'

         FileUtils.mkdir_p(testpath('a/e/f'))
         keepdir
         File.exist?(testpath('a/e/.keep')).must_equal false
         File.ftype(testpath('a/e/f/.keep')).must_equal 'file'
      end

      it 'must print updated files in realpath (this may change)' do
         keepdir
         FileUtils.mkdir_p(testpath('a/e/f'))

         keepdir.must_equal <<EOF
delete #{testpath('a/e/.keep')}
create #{testpath('a/e/f/.keep')}
EOF
      end
   end

   describe '--dry-run' do
      it 'must not create keepfiles for empty directory' do
         keepdir '--dry-run'
         File.exist?(testpath('a/b/c/.keep')).must_equal false
         File.exist?(testpath('a/d/.keep')).must_equal false
         File.exist?(testpath('a/e/.keep')).must_equal false
      end

      it 'must print created files in realpath (this may change)' do
         keepdir('--dry-run').must_equal <<EOF
create #{testpath('a/b/c/.keep')}
create #{testpath('a/d/.keep')}
create #{testpath('a/e/.keep')}
EOF
      end

      it 'must suppress output with -q' do
         keepdir('--dry-run', '-q').lines.must_be :empty?
      end

      it 'must print updated files in realpath (this may change)' do
         keepdir
         FileUtils.mkdir_p(testpath('a/e/f'))

         keepdir('--dry-run').must_equal <<EOF
delete #{testpath('a/e/.keep')}
create #{testpath('a/e/f/.keep')}
EOF
      end
   end

   describe '--purge' do
      it 'must delete all keepfiles' do
         keepdir
         keepdir '--purge'
         File.exist?(testpath('a/b/c/.keep')).must_equal false
         File.exist?(testpath('a/d/.keep')).must_equal false
         File.exist?(testpath('a/e/.keep')).must_equal false
      end

      it 'must print deleted files in realpath (this may change)' do
         keepdir
         keepdir('--purge').must_equal <<EOF
delete #{testpath('a/b/c/.keep')}
delete #{testpath('a/d/.keep')}
delete #{testpath('a/e/.keep')}
EOF
      end

      it 'must suppress output with -q' do
         keepdir
         keepdir('--purge', '-q').lines.must_be :empty?
      end
   end

   describe '--purge --dry-run' do
      it 'must not delete keepfiles' do
         keepdir
         keepdir '--purge', '--dry-run'
         File.exist?(testpath('a/b/c/.keep')).must_equal true
         File.exist?(testpath('a/d/.keep')).must_equal true
         File.exist?(testpath('a/e/.keep')).must_equal true
      end

      it 'must print files to be deleted in realpath (this may change)' do
         keepdir
         keepdir('--purge', '--dry-run').must_equal <<EOF
delete #{testpath('a/b/c/.keep')}
delete #{testpath('a/d/.keep')}
delete #{testpath('a/e/.keep')}
EOF
      end

      it 'must suppress output with -q' do
         keepdir('--purge', '--dry-run', '-q').lines.must_be :empty?
      end
   end

   describe 'specify directory' do
      it 'must accept starting directory as an argument' do
         keepdir testpath('a/b')
         File.exist?(testpath('a/b/c/.keep')).must_equal true
         File.exist?(testpath('a/d/.keep')).must_equal false
         File.exist?(testpath('a/e/.keep')).must_equal false
      end
   end

   describe '--no-prune' do
      it 'must clear prune list' do
         keepdir '--no-prune'
         File.exist?(testpath('a/b/c/.keep')).must_equal true
         File.exist?(testpath('a/d/.keep')).must_equal true
         File.exist?(testpath('a/e/.keep')).must_equal true
         File.exist?(testpath('a/.git/.keep')).must_equal true
         File.exist?(testpath('a/b/.git/f/.keep')).must_equal true
      end

      it 'must not have effect to preceding --prune' do
         keepdir '--prune=b', '--no-prune'
         File.exist?(testpath('a/b/c/.keep')).must_equal true
         File.exist?(testpath('a/d/.keep')).must_equal true
         File.exist?(testpath('a/e/.keep')).must_equal true
         File.exist?(testpath('a/.git/.keep')).must_equal true
         File.exist?(testpath('a/b/.git/f/.keep')).must_equal true
      end

      it 'must not have effect to following --prune' do
         keepdir '--no-prune', '--prune=b'
         File.exist?(testpath('a/b/c/.keep')).must_equal false
         File.exist?(testpath('a/d/.keep')).must_equal true
         File.exist?(testpath('a/e/.keep')).must_equal true
         File.exist?(testpath('a/.git/.keep')).must_equal true
         File.exist?(testpath('a/b/.git/f/.keep')).must_equal false
      end
   end

   describe '--create-hook, --delete-hook' do
      it 'must be called after create/delete' do
         keepdir('--update',
                 '--create-hook=echo +',
                 '--delete-hook=echo -').must_equal <<EOF
create #{testpath('a/b/c/.keep')}
+ #{testpath('a/b/c/.keep')}
create #{testpath('a/d/.keep')}
+ #{testpath('a/d/.keep')}
create #{testpath('a/e/.keep')}
+ #{testpath('a/e/.keep')}
EOF
         keepdir('--purge',
                 '--create-hook=echo +',
                 '--delete-hook=echo -').must_equal <<EOF
delete #{testpath('a/b/c/.keep')}
- #{testpath('a/b/c/.keep')}
delete #{testpath('a/d/.keep')}
- #{testpath('a/d/.keep')}
delete #{testpath('a/e/.keep')}
- #{testpath('a/e/.keep')}
EOF
      end

      it 'must be called first-specified-first' do
         keepdir('--update',
                 '--create-hook=echo 1.',
                 '--create-hook=echo 2.',
                 '--delete-hook=echo 1.',
                 '--delete-hook=echo 2.'
                ).must_equal <<EOF
create #{testpath('a/b/c/.keep')}
1. #{testpath('a/b/c/.keep')}
2. #{testpath('a/b/c/.keep')}
create #{testpath('a/d/.keep')}
1. #{testpath('a/d/.keep')}
2. #{testpath('a/d/.keep')}
create #{testpath('a/e/.keep')}
1. #{testpath('a/e/.keep')}
2. #{testpath('a/e/.keep')}
EOF
         keepdir('--purge',
                 '--create-hook=echo 1.',
                 '--create-hook=echo 2.',
                 '--delete-hook=echo 1.',
                 '--delete-hook=echo 2.'
                ).must_equal <<EOF
delete #{testpath('a/b/c/.keep')}
1. #{testpath('a/b/c/.keep')}
2. #{testpath('a/b/c/.keep')}
delete #{testpath('a/d/.keep')}
1. #{testpath('a/d/.keep')}
2. #{testpath('a/d/.keep')}
delete #{testpath('a/e/.keep')}
1. #{testpath('a/e/.keep')}
2. #{testpath('a/e/.keep')}
EOF
      end
   end

   describe '--replace' do
      it 'can specify REPLSTR' do
         keepdir('--update',
                 '--replace=%',
                 '--create-hook=echo %+',
                 '--delete-hook=echo %-').must_equal <<EOF
create #{testpath('a/b/c/.keep')}
#{testpath('a/b/c/.keep')}+
create #{testpath('a/d/.keep')}
#{testpath('a/d/.keep')}+
create #{testpath('a/e/.keep')}
#{testpath('a/e/.keep')}+
EOF
         keepdir('--purge',
                 '--replace=%',
                 '--create-hook=echo %+',
                 '--delete-hook=echo %-').must_equal <<EOF
delete #{testpath('a/b/c/.keep')}
#{testpath('a/b/c/.keep')}-
delete #{testpath('a/d/.keep')}
#{testpath('a/d/.keep')}-
delete #{testpath('a/e/.keep')}
#{testpath('a/e/.keep')}-
EOF
      end

      it 'must replace only first occurence of REPLSTR' do
         keepdir('--update',
                 '--replace=%',
                 '--create-hook=echo %%+%',
                 '--delete-hook=echo %%-%').must_equal <<EOF
create #{testpath('a/b/c/.keep')}
#{testpath('a/b/c/.keep')}%+%
create #{testpath('a/d/.keep')}
#{testpath('a/d/.keep')}%+%
create #{testpath('a/e/.keep')}
#{testpath('a/e/.keep')}%+%
EOF
         keepdir('--purge',
                 '--replace=%',
                 '--create-hook=echo %%+%',
                 '--delete-hook=echo %%-%').must_equal <<EOF
delete #{testpath('a/b/c/.keep')}
#{testpath('a/b/c/.keep')}%-%
delete #{testpath('a/d/.keep')}
#{testpath('a/d/.keep')}%-%
delete #{testpath('a/e/.keep')}
#{testpath('a/e/.keep')}%-%
EOF
      end

      it 'cannot change REPLSTR' do
         keepdir_status('--replace=%', '--replace=+').must_be :!=, 0
      end

      it 'is ok to specify same REPLSTR' do
         keepdir_status('--replace=%', '--replace=%').must_be :==, 0
      end

      it 'is error to specify empty REPLSTR' do
         keepdir_status('--replace=').must_be :!=, 0
      end
   end

   describe '--exclude' do
      it 'must exclude directories in command output' do
         keepdir '--exclude=echo a/b'
         File.exist?(testpath('a/b/c/.keep')).must_equal false
         File.exist?(testpath('a/d/.keep')).must_equal true
         File.exist?(testpath('a/e/.keep')).must_equal true
      end

      it 'must interpret paths relative to .' do
         keepdir '--exclude=echo b'
         File.exist?(testpath('a/b/c/.keep')).must_equal true
         File.exist?(testpath('a/d/.keep')).must_equal true
         File.exist?(testpath('a/e/.keep')).must_equal true
      end

      it 'must accept absolute paths' do
         keepdir "--exclude=echo #{testpath('a/b')}"
         File.exist?(testpath('a/b/c/.keep')).must_equal false
         File.exist?(testpath('a/d/.keep')).must_equal true
         File.exist?(testpath('a/e/.keep')).must_equal true
      end

      it 'must accept lines of paths' do
         tf = begin
                 tf = Tempfile.new("test.exclude")
                 tf.puts testpath('a/b')
                 tf.puts 'a/d'
                 tf.puts 'e'
                 tf
              ensure
                 tf.close
              end
         keepdir "--exclude=cat #{tf.path}"
         File.exist?(testpath('a/b/c/.keep')).must_equal false
         File.exist?(testpath('a/d/.keep')).must_equal false
         File.exist?(testpath('a/e/.keep')).must_equal true
      end
   end

   describe '--interactive' do
      it 'must recognize y as accept' do
         yes_keepdir('y', '--interactive')
         File.exist?(testpath('a/b/c/.keep')).must_equal true
         File.exist?(testpath('a/d/.keep')).must_equal true
         File.exist?(testpath('a/e/.keep')).must_equal true
      end

      it 'must recognize Y as accept too' do
         yes_keepdir('Y', '--interactive')
         File.exist?(testpath('a/b/c/.keep')).must_equal true
         File.exist?(testpath('a/d/.keep')).must_equal true
         File.exist?(testpath('a/e/.keep')).must_equal true
      end

      it 'does not recognize any input other than y/Y as accept (n)' do
         yes_keepdir('n', '--interactive')
         File.exist?(testpath('a/b/c/.keep')).must_equal false
         File.exist?(testpath('a/d/.keep')).must_equal false
         File.exist?(testpath('a/e/.keep')).must_equal false
      end

      it 'does not recognize any input other than y/Y as accept (N)' do
         yes_keepdir('N', '--interactive')
         File.exist?(testpath('a/b/c/.keep')).must_equal false
         File.exist?(testpath('a/d/.keep')).must_equal false
         File.exist?(testpath('a/e/.keep')).must_equal false
      end

      it 'does not recognize any input other than y/Y as accept (yes)' do
         yes_keepdir('yes', '--interactive')
         File.exist?(testpath('a/b/c/.keep')).must_equal false
         File.exist?(testpath('a/d/.keep')).must_equal false
         File.exist?(testpath('a/e/.keep')).must_equal false
      end

      it 'exits program at eof' do
         eof_keepdir('--interactive') \
            .must_equal "create #{testpath('a/b/c/.keep')}? "
         File.exist?(testpath('a/b/c/.keep')).must_equal false
         File.exist?(testpath('a/d/.keep')).must_equal false
         File.exist?(testpath('a/e/.keep')).must_equal false
      end
   end
end

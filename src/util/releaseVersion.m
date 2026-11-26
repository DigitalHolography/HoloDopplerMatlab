function releaseVersion(versionTag)
% releaseVersion - Update version.txt, push to main, and create a tag.
%
% Usage:
%   releaseVersion('v1.2.3')

if nargin < 1
    error('Usage: releaseVersion(''vX.Y.Z'')');
end

% Step 1: Update version.txt
fid = fopen('version.txt', 'w');

if fid == -1
    error('Cannot open version.txt for writing');
end

fprintf(fid, '%s\n', versionTag);
fclose(fid);
fprintf('Updated version.txt with version %s\n', versionTag);

% Step 2: Commit and push to main
cmdCheckout = 'git checkout main';
cmdAdd = 'git add version.txt';
cmdCommit = sprintf('git commit -m "chore: update version.txt to %s"', versionTag);
cmdPush = 'git push origin main';

[status, cmdout] = system(cmdCheckout);
assert(status == 0, cmdout);

[status, cmdout] = system(cmdAdd);
assert(status == 0, cmdout);

[status, cmdout] = system(cmdCommit);

if status ~= 0
    disp('No changes to commit.');
end

[status, cmdout] = system(cmdPush);
assert(status == 0, cmdout);
fprintf('Changes pushed to main\n');

% Step 3: Create and push tag
cmdTag = sprintf('git tag %s', versionTag);
cmdPushTag = sprintf('git push origin %s', versionTag);

[status, cmdout] = system(cmdTag);
assert(status == 0, cmdout);

[status, cmdout] = system(cmdPushTag);
assert(status == 0, cmdout);
fprintf('Created and pushed tag %s\n', versionTag);

fprintf('Release process completed successfully!\n');

end

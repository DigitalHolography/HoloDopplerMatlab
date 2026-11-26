function highest_number = get_highest_number_in_files(directory, search_str)
% Initialize the highest number to be -Inf (so it can be updated)
highest_number = 0;

% List all files in the directory
files = dir(directory);

% Loop through all the files
for i = 1:numel(files)
    % Get the file name
    file_name = files(i).name;

    % Check if the file name contains the search string and is a regular file
    if contains(file_name, search_str) && ~files(i).isdir

        [~, file_name, ~] = fileparts(file_name);
        % Use a regular expression to find numbers at the end of the file name
        tokens = regexp(file_name, '(\d+)$', 'tokens');

        % If a number is found at the end of the file name
        if ~isempty(tokens)
            % Extract the number (from the first token in the cell array)
            num = str2double(tokens{1}{1});

            % Update the highest number if the current number is higher
            if num > highest_number
                highest_number = num;
            end

        end

    end

end

% If no valid number is found, return a message or default value (e.g., -Inf)
if highest_number == 0
    % disp('No files with the specified string and a number at the end were found.');
end

end
